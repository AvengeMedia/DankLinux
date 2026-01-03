#!/bin/bash
# Common utilities for OBS build automation
# Provides logging, error handling, and utility functions

# Source guard to prevent multiple sourcing
if [[ -n "${_OBS_COMMON_SOURCED:-}" ]]; then
    return 0
fi
readonly _OBS_COMMON_SOURCED=1

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'  # No Color

# Error codes
readonly ERR_CONFIG=1
readonly ERR_API_RATE_LIMIT=2
readonly ERR_NETWORK=3
readonly ERR_HASH_MISMATCH=4
readonly ERR_BUILD_FAILURE=5
readonly ERR_UPLOAD_FAILURE=6
readonly ERR_PARTIAL_FAILURE=7

# Global error tracking
declare -gA PACKAGE_ERRORS
declare -gi TOTAL_PACKAGES=0
declare -gi FAILED_PACKAGES=0

# Temp directory management
TEMP_DIR=""

# Cache directory
readonly CACHE_DIR="$HOME/.cache/obs-automation"
readonly CACHE_TTL=900  # 15 minutes

# Logging functions
log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Track package error
track_error() {
    local package="$1"
    local error_code="$2"
    local error_msg="$3"

    PACKAGE_ERRORS["$package"]="$error_code|$error_msg"
    FAILED_PACKAGES=$((FAILED_PACKAGES + 1))

    log_error "$package: $error_msg (code: $error_code)"
}

# Report final status
report_status() {
    log_info "=========================================="
    log_info "Build Summary"
    log_info "=========================================="
    log_info "Total packages: $TOTAL_PACKAGES"
    log_info "Successful: $((TOTAL_PACKAGES - FAILED_PACKAGES))"
    log_info "Failed: $FAILED_PACKAGES"

    if [[ $FAILED_PACKAGES -gt 0 ]]; then
        log_info ""
        log_info "Failed packages:"
        for pkg in "${!PACKAGE_ERRORS[@]}"; do
            local error_info="${PACKAGE_ERRORS[$pkg]}"
            local error_code="${error_info%%|*}"
            local error_msg="${error_info##*|}"
            log_error "  - $pkg: $error_msg (code: $error_code)"
        done

        # Partial failure if some succeeded
        if [[ $FAILED_PACKAGES -lt $TOTAL_PACKAGES ]]; then
            exit $ERR_PARTIAL_FAILURE
        else
            exit $ERR_BUILD_FAILURE
        fi
    fi

    exit 0
}

# Create temp directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d -t obs-build-XXXXXXXXXX)
    log_debug "Created temp directory: $TEMP_DIR"
    echo "$TEMP_DIR"
}

# Clean up temp directory
cleanup_temp() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log_debug "Cleaning up temp directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Cache management
init_cache() {
    mkdir -p "$CACHE_DIR"
}

get_cache() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"

    if [[ -f "$cache_file" ]]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)))
        if [[ $age -lt $CACHE_TTL ]]; then
            cat "$cache_file"
            return 0
        else
            log_debug "Cache expired for key: $key (age: ${age}s)"
            rm -f "$cache_file"
        fi
    fi

    return 1
}

set_cache() {
    local key="$1"
    local value="$2"
    local cache_file="$CACHE_DIR/$key"

    mkdir -p "$CACHE_DIR"
    echo "$value" > "$cache_file"
    log_debug "Cached value for key: $key"
}

clear_old_cache() {
    if [[ -d "$CACHE_DIR" ]]; then
        find "$CACHE_DIR" -type f -mmin +$((CACHE_TTL / 60)) -delete 2>/dev/null || true
    fi
}

clear_package_cache() {
    local package="$1"
    if [[ -d "$CACHE_DIR" ]]; then
        # Clear all cache entries related to this package
        rm -f "$CACHE_DIR"/*"${package}"* 2>/dev/null || true
        log_debug "Cleared cache for package: $package"
    fi
}

# Cleanup trap
cleanup() {
    local exit_code=$?

    cleanup_temp
    clear_old_cache

    if [[ $exit_code -eq 0 ]]; then
        log_debug "Script completed successfully"
    else
        log_debug "Script failed with exit code $exit_code"
    fi
}

trap cleanup EXIT

# Validate required commands
require_command() {
    local cmd="$1"
    local pkg="${2:-$cmd}"

    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found. Please install $pkg."
        exit $ERR_CONFIG
    fi
}

# Validate required environment variables
require_env() {
    local var="$1"

    if [[ -z "${!var:-}" ]]; then
        log_error "Required environment variable $var is not set"
        exit $ERR_CONFIG
    fi
}

# Safe directory change
safe_cd() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_error "Directory does not exist: $dir"
        return 1
    fi

    cd "$dir" || {
        log_error "Failed to change to directory: $dir"
        return 1
    }

    log_debug "Changed to directory: $dir"
}

# Get script directory (for relative imports)
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)"
}

# Get repository root
get_repo_root() {
    local script_dir
    script_dir=$(get_script_dir)
    echo "$(cd "$script_dir/../../../.." && pwd)"
}

# Confirm action (for interactive mode)
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    # Non-interactive mode (CI)
    if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
        return 0
    fi

    local yn
    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n]: " yn
        yn=${yn:-y}
    else
        read -p "$prompt [y/N]: " yn
        yn=${yn:-n}
    fi

    case $yn in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Print separator line
print_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "$width" | tr ' ' "$char" >&2
}

# Check if running in CI
is_ci() {
    [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]
}

# Initialize common module
init_common() {
    init_cache
    log_debug "Common module initialized"
}
