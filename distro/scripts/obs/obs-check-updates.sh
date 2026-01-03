#!/bin/bash
# OBS Package Update Checker
# Detects which packages need updates by comparing upstream versions with OBS
# This script ELIMINATES FALSE POSITIVES by properly stripping .db suffixes

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/version.sh
source "$SCRIPT_DIR/lib/version.sh"
# shellcheck source=./lib/package-config.sh
source "$SCRIPT_DIR/lib/package-config.sh"
# shellcheck source=./lib/api.sh
source "$SCRIPT_DIR/lib/api.sh"

# Initialize
init_common

# Command-line options
OUTPUT_JSON=false
VERBOSE=false

# Usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [PACKAGE...]

Check for package updates on OBS.

ARGUMENTS:
  PACKAGE       Package name(s) to check, "all", or group name
                (default: all packages)

OPTIONS:
  --json        Output results as JSON
  --verbose     Enable verbose output
  -h, --help    Show this help message

EXAMPLES:
  $(basename "$0")                    # Check all packages
  $(basename "$0") niri-git
  $(basename "$0") --json all-git
  $(basename "$0") niri-git quickshell-git xwayland-satellite-git

EOF
    exit 0
}

# Parse command-line arguments
PACKAGES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
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
            PACKAGES+=("$1")
            shift
            ;;
    esac
done

# Default to all packages if none specified
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    PACKAGES=("all")
fi

# Expand package selectors
EXPANDED_PACKAGES=()
for selector in "${PACKAGES[@]}"; do
    expanded=$(expand_package_selector "$selector")
    if [[ $? -eq 0 ]]; then
        EXPANDED_PACKAGES+=($expanded)
    else
        log_error "Failed to expand package selector: $selector"
        exit $ERR_CONFIG
    fi
done

# Remove duplicates
EXPANDED_PACKAGES=($(echo "${EXPANDED_PACKAGES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

log_info "Checking ${#EXPANDED_PACKAGES[@]} package(s) for updates"

# Results array for JSON output
declare -a UPDATE_RESULTS=()

# Check each package for updates
check_package_updates() {
    local package="$1"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Checking: $package"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Load package configuration
    local config=$(load_package_config "$package")
    if [[ $? -ne 0 ]]; then
        log_error "$package: Failed to load configuration"
        return 1
    fi

    local package_type=$(echo "$config" | yq eval '.type' -)
    local upstream_repo=$(echo "$config" | yq eval '.upstream.repo' -)

    log_debug "Package type: $package_type"
    log_debug "Upstream repo: $upstream_repo"

    # Get upstream version
    local upstream_version=""
    local upstream_commit=""
    local commit_count=""

    if [[ "$package_type" == "git" ]]; then
        # Git package: get latest commit
        local branch=$(echo "$config" | yq eval '.upstream.branch // "main"' -)

        log_info "  Fetching latest commit from $upstream_repo@$branch..."
        upstream_commit=$(get_latest_commit "$upstream_repo" "$branch")

        if [[ $? -ne 0 || -z "$upstream_commit" ]]; then
            log_error "$package: Failed to fetch latest commit"
            return 1
        fi

        log_info "  Latest commit: $upstream_commit"

        # Get commit count
        commit_count=$(get_commit_count "$upstream_repo" "$branch")
        log_debug "Commit count: $commit_count"

        # Determine base version
        local base_version_source=$(get_base_version_source "$package")
        local base_version=""

        if [[ "$base_version_source" == "pin" ]]; then
            # Use pinned base version
            base_version=$(get_pin_info "$package" "base_version")
            log_info "  Base version (from pin): $base_version"

        elif [[ "$base_version_source" =~ ^stable:(.+)$ ]]; then
            # Get from stable package
            local stable_pkg="${BASH_REMATCH[1]}"
            log_debug "Getting base version from stable package: $stable_pkg"

            # Get the stable package's upstream repo
            local stable_repo=$(get_upstream_repo "$stable_pkg")

            if [[ -z "$stable_repo" ]]; then
                log_warn "Could not find upstream repo for stable package: $stable_pkg"
                base_version=$(echo "$config" | yq eval '.base_version.fallback' -)
                log_warn "Using fallback: $base_version"
            else
                base_version=$(get_latest_release "$stable_repo" 2>/dev/null || echo "")

                if [[ -z "$base_version" ]]; then
                    # Fall back to config fallback
                    base_version=$(echo "$config" | yq eval '.base_version.fallback' -)
                    log_warn "Could not get stable version from $stable_repo, using fallback: $base_version"
                else
                    log_info "  Base version (from $stable_pkg): $base_version"
                fi
            fi

        elif [[ "$base_version_source" =~ ^fallback:(.+)$ ]]; then
            base_version="${BASH_REMATCH[1]}"
            log_info "  Base version (fallback): $base_version"
        fi

        # Build git version string (without .db suffix - only add that when building)
        upstream_version="${base_version}+git${commit_count}.${upstream_commit}"
        log_info "  Upstream version: $upstream_version"

    else
        # Stable package: check if pinned first
        if is_package_pinned "$package"; then
            log_info "  Package is pinned, skipping update check"

            # Get current OBS version for rebuild support
            local obs_version=$(get_obs_version "$package" 2>/dev/null || echo "")

            log_success "$package: Pinned to specific commit → UP TO DATE"

            UPDATE_RESULTS+=("$(cat <<EOF
{
  "package": "$package",
  "needs_update": false,
  "pinned": true,
  "reason": "Package pinned in pins.yaml",
  "obs_version": $(if [[ -n "$obs_version" ]]; then echo "\"$obs_version\""; else echo "null"; fi)
}
EOF
            )")
            return 0
        fi

        # Stable package: get latest release
        local source_type=$(echo "$config" | yq eval '.upstream.source_type // "github_release"' -)

        if [[ "$source_type" == "custom" ]]; then
            # Custom source: try git tags as fallback
            log_info "  Custom source detected, fetching latest tag from $upstream_repo..."
            upstream_version=$(get_latest_tag "$upstream_repo")

            if [[ $? -ne 0 || -z "$upstream_version" ]]; then
                log_error "$package: Failed to fetch latest tag"
                return 1
            fi

            log_info "  Latest tag: $upstream_version"
        else
            # GitHub release
            log_info "  Fetching latest release from $upstream_repo..."
            upstream_version=$(get_latest_release "$upstream_repo")

            if [[ $? -ne 0 || -z "$upstream_version" ]]; then
                log_error "$package: Failed to fetch latest release"
                return 1
            fi

            log_info "  Latest release: $upstream_version"
        fi

        # Don't add .db suffix yet - only add it when building/uploading
        # For version comparison, keep it clean
    fi

    # Get OBS version
    log_info "  Checking current version on OBS..."
    local obs_version=$(get_obs_version "$package" 2>/dev/null || echo "")

    if [[ -z "$obs_version" ]]; then
        log_success "$package: Not found on OBS (new package) → NEEDS UPDATE"

        UPDATE_RESULTS+=("$(cat <<EOF
{
  "package": "$package",
  "needs_update": true,
  "reason": "new_package",
  "upstream_version": "$upstream_version",
  "upstream_commit": "$upstream_commit",
  "obs_version": null
}
EOF
        )")
        return 0
    fi

    log_info "  Current OBS version: $obs_version"

    # Compare versions (strip db suffixes first!)
    local upstream_clean=$(normalize_version "$upstream_version")
    local obs_clean=$(normalize_version "$obs_version")

    log_debug "Comparing versions (after stripping .db):"
    log_debug "  Upstream clean: $upstream_clean"
    log_debug "  OBS clean:      $obs_clean"

    local needs_update=false
    local reason=""

    if [[ "$package_type" == "git" ]]; then
        # Git package: compare commit hashes
        local upstream_hash=$(extract_commit_hash "$upstream_clean")
        local obs_hash=$(extract_commit_hash "$obs_clean")

        log_debug "Comparing commit hashes:"
        log_debug "  Upstream: $upstream_hash"
        log_debug "  OBS:      $obs_hash"

        if [[ "$upstream_hash" != "$obs_hash" ]]; then
            log_success "$package: New commit detected → NEEDS UPDATE"
            log_info "  $obs_hash → $upstream_hash"
            needs_update=true
            reason="new_commit"
        else
            log_info "$package: Already at latest commit ($upstream_hash) → UP TO DATE"
        fi

    else
        # Stable package: compare version strings
        if [[ "$upstream_clean" != "$obs_clean" ]]; then
            log_success "$package: New version detected → NEEDS UPDATE"
            log_info "  $obs_clean → $upstream_clean"
            needs_update=true
            reason="new_version"
        else
            log_info "$package: Already at latest version ($upstream_clean) → UP TO DATE"
        fi
    fi

    # Store result
    UPDATE_RESULTS+=("$(cat <<EOF
{
  "package": "$package",
  "needs_update": $needs_update,
  "reason": "$reason",
  "upstream_version": "$upstream_version",
  "upstream_commit": "$upstream_commit",
  "obs_version": "$obs_version",
  "obs_commit": "$(extract_commit_hash "$obs_clean" 2>/dev/null || echo "")"
}
EOF
    )")

    echo ""  # Blank line between packages
}

# Check all packages
for package in "${EXPANDED_PACKAGES[@]}"; do
    check_package_updates "$package"
done

# Generate output
if [[ "$OUTPUT_JSON" == "true" ]]; then
    # JSON output
    echo "["
    first=true
    for result in "${UPDATE_RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "$result"
    done
    echo "]"
else
    # Summary output
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Update Check Summary"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    total=${#EXPANDED_PACKAGES[@]}
    needs_update=0

    for result in "${UPDATE_RESULTS[@]}"; do
        pkg=$(echo "$result" | grep -oP '"package":\s*"\K[^"]+')
        update=$(echo "$result" | grep -oP '"needs_update":\s*\K(true|false)')

        if [[ "$update" == "true" ]]; then
            needs_update=$((needs_update + 1))
            log_success "  ✓ $pkg"
        else
            log_info "  - $pkg (up to date)"
        fi
    done

    echo ""
    log_info "Total packages checked: $total"
    log_info "Packages needing updates: $needs_update"
    log_info "Packages up to date: $((total - needs_update))"

    if [[ $needs_update -eq 0 ]]; then
        log_success "All packages are up to date!"
        exit 0
    else
        log_info "Run builds for packages listed above."
        exit 0
    fi
fi
