#!/bin/bash
# Package configuration loader
# Loads and validates obs-packages.yaml and merges with pins.yaml

# Source guard to prevent multiple sourcing
if [[ -n "${_OBS_PACKAGE_CONFIG_SOURCED:-}" ]]; then
    return 0
fi
readonly _OBS_PACKAGE_CONFIG_SOURCED=1

# Source common utilities
_PKG_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$_PKG_CONFIG_LIB_DIR/common.sh"

# Configuration file paths
REPO_ROOT=$(get_repo_root)
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/distro/config/obs-packages.yaml}"
PINS_FILE="${PINS_FILE:-$REPO_ROOT/distro/pins.yaml}"

# Check if yq is available
check_yq() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed"
        log_error "Install with: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        log_error "             sudo chmod +x /usr/local/bin/yq"
        exit $ERR_CONFIG
    fi
}

# Validate configuration file exists
validate_config_file() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit $ERR_CONFIG
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$CONFIG_FILE" &> /dev/null; then
        log_error "Invalid YAML syntax in configuration file: $CONFIG_FILE"
        exit $ERR_CONFIG
    fi

    log_debug "Configuration file validated: $CONFIG_FILE"
}

# Load package configuration
# Returns: YAML output of package configuration
load_package_config() {
    local package="$1"

    check_yq
    validate_config_file

    # Get package config
    local config=$(yq eval ".packages.$package" "$CONFIG_FILE" 2>/dev/null)

    if [[ "$config" == "null" || -z "$config" ]]; then
        log_error "Package '$package' not found in configuration"
        log_error "Available packages: $(list_packages)"
        return 1
    fi

    # Check if package uses pins
    local uses_pins=$(echo "$config" | yq eval '.base_version.from_pins // false' -)

    if [[ "$uses_pins" == "true" && -f "$PINS_FILE" ]]; then
        log_debug "Checking pins.yaml for $package"

        # Get base package name (strip -git suffix for pin lookup)
        local base_package="${package%-git}"
        local pin_config=$(yq eval ".$base_package" "$PINS_FILE" 2>/dev/null)

        if [[ "$pin_config" != "null" && -n "$pin_config" ]]; then
            local pin_enabled=$(echo "$pin_config" | yq eval '.enabled // false' -)

            if [[ "$pin_enabled" == "true" ]]; then
                log_debug "$base_package: Pin is enabled in pins.yaml"

                # Merge pin data into config (as separate pin_info section)
                config=$(echo "$config" | yq eval ". += {\"pin_info\": $(echo "$pin_config" | yq eval -o=json .)}" -)
            fi
        fi
    fi

    echo "$config"
}

# Get package type (git or stable)
get_package_type() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.type // "stable"' -
}

# Get upstream repository
get_upstream_repo() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.upstream.repo' -
}

# Get upstream branch (for git packages)
get_upstream_branch() {
    local package="$1"
    local config=$(load_package_config "$package")

    local branch=$(echo "$config" | yq eval '.upstream.branch // "main"' -)
    echo "$branch"
}

# Get supported distros for package
get_package_distros() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.distros[]' - | tr '\n' ' '
}

# Check if package supports a distro
package_supports_distro() {
    local package="$1"
    local distro="$2"

    local distros=$(get_package_distros "$package")

    if echo "$distros" | grep -qw "$distro"; then
        return 0
    else
        return 1
    fi
}

# Get base version source for git packages
get_base_version_source() {
    local package="$1"
    local config=$(load_package_config "$package")

    # Check for pin first
    local has_pin=$(echo "$config" | yq eval '.pin_info.enabled // false' -)
    if [[ "$has_pin" == "true" ]]; then
        echo "pin"
        return 0
    fi

    # Check from_stable
    local from_stable=$(echo "$config" | yq eval '.base_version.from_stable // ""' -)
    if [[ -n "$from_stable" ]]; then
        echo "stable:$from_stable"
        return 0
    fi

    # Fall back to hardcoded
    local fallback=$(echo "$config" | yq eval '.base_version.fallback // ""' -)
    if [[ -n "$fallback" ]]; then
        echo "fallback:$fallback"
        return 0
    fi

    log_error "No base version source defined for $package"
    return 1
}

# Get pinned commit info (if package is pinned)
get_pin_info() {
    local package="$1"
    local field="$2"  # commit, commit_count, base_version, snap_date

    local config=$(load_package_config "$package")

    echo "$config" | yq eval ".pin_info.$field // \"\"" -
}

# Check if package has pin enabled
is_package_pinned() {
    local package="$1"
    local config=$(load_package_config "$package")

    local pin_enabled=$(echo "$config" | yq eval '.pin_info.enabled // false' -)

    if [[ "$pin_enabled" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Get build language
get_build_language() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.build.language // "unknown"' -
}

# Check if package requires vendored dependencies
requires_vendor_deps() {
    local package="$1"
    local config=$(load_package_config "$package")

    local vendor=$(echo "$config" | yq eval '.build.vendor_deps // false' -)

    if [[ "$vendor" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Get tarball directory name template
get_tarball_directory() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.tarball.directory_name // ""' -
}

# Get tarball compression type
get_tarball_compression() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.tarball.compression // "gz"' -
}

# List all packages
list_packages() {
    check_yq
    validate_config_file

    yq eval '.packages | keys | .[]' "$CONFIG_FILE" | tr '\n' ' '
}

# List packages in a group
list_package_group() {
    local group="$1"

    check_yq
    validate_config_file

    yq eval ".groups.$group[]" "$CONFIG_FILE" 2>/dev/null | tr '\n' ' '
}

# Expand package selector (handles "all", group names, or package names)
expand_package_selector() {
    local selector="$1"

    check_yq
    validate_config_file

    case "$selector" in
        all)
            list_package_group "all"
            ;;
        all-stable)
            list_package_group "all-stable"
            ;;
        all-git)
            list_package_group "all-git"
            ;;
        *)
            # Check if it's a group name
            local group_packages=$(list_package_group "$selector" 2>/dev/null)
            if [[ -n "$group_packages" ]]; then
                echo "$group_packages"
            else
                # Treat as individual package name
                # Validate package exists
                local config=$(yq eval ".packages.$selector" "$CONFIG_FILE" 2>/dev/null)
                if [[ "$config" != "null" && -n "$config" ]]; then
                    echo "$selector"
                else
                    log_error "Unknown package or group: $selector"
                    return 1
                fi
            fi
            ;;
    esac
}

# Validate package exists
validate_package() {
    local package="$1"

    check_yq

    local config=$(yq eval ".packages.$package" "$CONFIG_FILE" 2>/dev/null)

    if [[ "$config" == "null" || -z "$config" ]]; then
        return 1
    else
        return 0
    fi
}

# Get default configuration value
get_default() {
    local key="$1"

    check_yq
    validate_config_file

    yq eval ".defaults.$key" "$CONFIG_FILE" 2>/dev/null
}

# Get OBS project name
get_obs_project() {
    get_default "obs.project"
}

# Get source type (github_release, custom, etc.)
get_source_type() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.upstream.source_type // "github_release"' -
}

# Get custom URL template (for packages with custom download URLs)
get_url_template() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.upstream.url_template // ""' -
}

# Check if package is binary release
is_binary_release() {
    local package="$1"
    local config=$(load_package_config "$package")

    local binary=$(echo "$config" | yq eval '.build.binary_release // false' -)

    if [[ "$binary" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Get binary filename template
get_binary_template() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval '.build.binary_template // ""' -
}

# Get package full configuration as JSON (for passing to other scripts)
get_package_config_json() {
    local package="$1"
    local config=$(load_package_config "$package")

    echo "$config" | yq eval -o=json '.'
}

# Print package summary
print_package_info() {
    local package="$1"

    if ! validate_package "$package"; then
        log_error "Package not found: $package"
        return 1
    fi

    local type=$(get_package_type "$package")
    local repo=$(get_upstream_repo "$package")
    local distros=$(get_package_distros "$package")
    local language=$(get_build_language "$package")

    log_info "Package: $package"
    log_info "  Type: $type"
    log_info "  Upstream: $repo"
    log_info "  Distros: $distros"
    log_info "  Language: $language"

    if [[ "$type" == "git" ]]; then
        local branch=$(get_upstream_branch "$package")
        local base_source=$(get_base_version_source "$package")
        log_info "  Branch: $branch"
        log_info "  Base version from: $base_source"
    fi

    if is_package_pinned "$package"; then
        local pin_commit=$(get_pin_info "$package" "commit")
        local pin_base=$(get_pin_info "$package" "base_version")
        log_info "  📌 Pinned: Yes"
        log_info "     Commit: ${pin_commit:0:8}"
        log_info "     Base: $pin_base"
    fi

    if requires_vendor_deps "$package"; then
        log_info "  Vendor deps: Yes"
    fi
}

# Module initialization flag
readonly PACKAGE_CONFIG_LOADED=true
