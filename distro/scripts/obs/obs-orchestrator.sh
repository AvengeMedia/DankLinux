#!/bin/bash
# OBS Build Orchestrator
# Main entry point for OBS build automation
# Coordinates update checking, building, and uploading

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/version.sh
source "$SCRIPT_DIR/lib/version.sh"
# shellcheck source=./lib/package-config.sh
source "$SCRIPT_DIR/lib/package-config.sh"

# Initialize
init_common

# Usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] PACKAGE [REBUILD_NUM] [DISTRO]

Build and upload packages to OBS.

ARGUMENTS:
  PACKAGE         Package name or "all"
  REBUILD_NUM     Rebuild number for .db suffix (e.g., 2, 3, 4)
  DISTRO          Target distro: debian, opensuse, or both (default: both)

OPTIONS:
  --message=MSG   Commit message
  --check-only    Only check for updates, don't build
  --verbose       Enable verbose output
  -h, --help      Show this help message

EXAMPLES:
  # Auto-detect latest version and build both distros
  $(basename "$0") niri-git

  # Rebuild with incremented .db suffix
  $(basename "$0") ghostty 2
  $(basename "$0") niri-git 3

  # Build specific distro
  $(basename "$0") ghostty 2 debian
  $(basename "$0") niri-git 2 opensuse

  # Build all packages with updates
  $(basename "$0") all

  # Check for updates only
  $(basename "$0") --check-only all

EOF
    exit 0
}

# Parse options
REBUILD_NUM=""
TARGET_DISTRO="both"
COMMIT_MESSAGE=""
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message=*)
            COMMIT_MESSAGE="${1#*=}"
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --verbose|-v)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Parse positional arguments
PACKAGE="${1:-}"
REBUILD_NUM="${2:-}"
TARGET_DISTRO="${3:-both}"

if [[ -z "$PACKAGE" ]]; then
    log_error "No package specified"
    usage
fi

# Validate rebuild number is numeric if provided
if [[ -n "$REBUILD_NUM" && ! "$REBUILD_NUM" =~ ^[0-9]+$ ]]; then
    log_error "Rebuild number must be numeric: $REBUILD_NUM"
    usage
fi

# Validate distro if provided
if [[ -n "$TARGET_DISTRO" && ! "$TARGET_DISTRO" =~ ^(debian|opensuse|both)$ ]]; then
    log_error "Invalid distro: $TARGET_DISTRO (must be: debian, opensuse, or both)"
    usage
fi

log_info "OBS Build Orchestrator"
log_info "Package: $PACKAGE"
[[ -n "$REBUILD_NUM" ]] && log_info "Rebuild number: $REBUILD_NUM"
[[ -n "$TARGET_DISTRO" && "$TARGET_DISTRO" != "both" ]] && log_info "Target distro: $TARGET_DISTRO"

# Expand package selector
PACKAGES=$(expand_package_selector "$PACKAGE")
if [[ $? -ne 0 ]]; then
    log_error "Failed to expand package selector: $PACKAGE"
    exit $ERR_CONFIG
fi

# Convert to array
read -ra PACKAGE_LIST <<< "$PACKAGES"

log_info "Building ${#PACKAGE_LIST[@]} package(s): ${PACKAGE_LIST[*]}"

# Function to build a single package
build_package() {
    local pkg="$1"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Processing: $pkg"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Determine version to build
    log_info "Auto-detecting version from upstream..."

    # Clear cache for this package to ensure fresh data from APIs
    clear_package_cache "$pkg"

    local check_output=$(mktemp)
    local version=""

    if [[ -n "$REBUILD_NUM" ]]; then
        # For rebuilds, get current version from OBS
        bash "$SCRIPT_DIR/obs-check-updates.sh" --json "$pkg" > "$check_output" 2>&1 || true

        # Extract only the JSON part (skip log messages)
        local json_output=$(sed -n '/^\[/,/^\]/p' "$check_output")
        version=$(echo "$json_output" | jq -r '.[0].obs_version // empty' 2>/dev/null)

        if [[ -z "$version" ]]; then
            log_error "Cannot determine current version for rebuild"
            rm -f "$check_output"
            return 1
        fi

        log_info "Current OBS version: $version"
    else
        # Normal build: check for updates
        bash "$SCRIPT_DIR/obs-check-updates.sh" --json "$pkg" > "$check_output" 2>&1

        # Extract only the JSON part (skip log messages that appear before the JSON array)
        local json_output=$(sed -n '/^\[/,/^\]/p' "$check_output")
        local needs_update=$(echo "$json_output" | jq -r '.[0].needs_update' 2>/dev/null)

        if [[ "$needs_update" != "true" ]]; then
            log_info "$pkg is already up to date, skipping"
            rm -f "$check_output"
            return 0
        fi

        version=$(echo "$json_output" | jq -r '.[0].upstream_version' 2>/dev/null)
    fi

    rm -f "$check_output"

    if [[ -z "$version" ]]; then
        log_error "Failed to determine version for $pkg"
        return 1
    fi

    log_info "Building version: $version"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        log_info "Check-only mode: Would build $pkg version $version"
        return 0
    fi

    # Create build output directory
    local build_dir=$(mktemp -d -t obs-build-$pkg-XXXXXXXXXX)
    log_debug "Build directory: $build_dir"

    # Build for target distros
    local build_success=true

    if [[ "$TARGET_DISTRO" == "both" || "$TARGET_DISTRO" == "debian" ]]; then
        if package_supports_distro "$pkg" "debian"; then
            log_info "Building Debian package..."

            local debian_dir="$build_dir/debian"
            mkdir -p "$debian_dir"

            local rebuild_flag=""
            [[ -n "$REBUILD_NUM" ]] && rebuild_flag="--rebuild=$REBUILD_NUM"

            if ! bash "$SCRIPT_DIR/obs-build-debian.sh" $rebuild_flag "$pkg" "$version" "$debian_dir"; then
                log_error "Debian build failed for $pkg"
                build_success=false
            else
                log_success "Debian build completed"
            fi
        fi
    fi

    if [[ "$TARGET_DISTRO" == "both" || "$TARGET_DISTRO" == "opensuse" ]]; then
        if package_supports_distro "$pkg" "opensuse"; then
            log_info "Building OpenSUSE package..."

            local opensuse_dir="$build_dir/opensuse"
            mkdir -p "$opensuse_dir"

            local rebuild_flag=""
            [[ -n "$REBUILD_NUM" ]] && rebuild_flag="--rebuild=$REBUILD_NUM"

            if ! bash "$SCRIPT_DIR/obs-build-opensuse.sh" $rebuild_flag "$pkg" "$version" "$opensuse_dir"; then
                log_error "OpenSUSE build failed for $pkg"
                build_success=false
            else
                log_success "OpenSUSE build completed"
            fi
        fi
    fi

    if [[ "$build_success" != "true" ]]; then
        rm -rf "$build_dir"
        return 1
    fi

    # Merge artifacts into single directory for upload
    local artifacts_dir="$build_dir/artifacts"
    mkdir -p "$artifacts_dir"

    [[ -d "$build_dir/debian" ]] && cp -r "$build_dir/debian"/* "$artifacts_dir/"
    [[ -d "$build_dir/opensuse" ]] && cp -r "$build_dir/opensuse"/* "$artifacts_dir/"

    # Upload to OBS
    log_info "Uploading to OBS..."

    local upload_cmd=("$SCRIPT_DIR/obs-upload.sh" "--distro=$TARGET_DISTRO")
    [[ -n "$COMMIT_MESSAGE" ]] && upload_cmd+=("--message=$COMMIT_MESSAGE")
    upload_cmd+=("$pkg" "$artifacts_dir")

    if ! bash "${upload_cmd[@]}"; then
        log_error "Upload failed for $pkg"
        rm -rf "$build_dir"
        return 1
    fi

    # Clean up
    rm -rf "$build_dir"

    log_success "$pkg processed successfully"
    return 0
}

# Process all packages
TOTAL_PACKAGES=${#PACKAGE_LIST[@]}
FAILED_PACKAGES=0

for pkg in "${PACKAGE_LIST[@]}"; do
    TOTAL_PACKAGES=$((TOTAL_PACKAGES))

    if ! build_package "$pkg"; then
        track_error "$pkg" $ERR_BUILD_FAILURE "Build or upload failed"
        FAILED_PACKAGES=$((FAILED_PACKAGES + 1))
    fi

    echo ""  # Blank line between packages
done

# Report final status
report_status
