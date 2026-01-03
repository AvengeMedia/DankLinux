#!/bin/bash
# Version parsing and comparison utilities
# Handles git and stable package versions with .db suffix support

# Source guard to prevent multiple sourcing
if [[ -n "${_OBS_VERSION_SOURCED:-}" ]]; then
    return 0
fi
readonly _OBS_VERSION_SOURCED=1

# Source common utilities
_VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$_VERSION_LIB_DIR/common.sh"

# Parse version string into components
parse_version() {
    local version="$1"
    local type="$2"  # "git" or "stable"

    if [[ "$type" == "git" ]]; then
        # Format: BASE+gitCOUNT.HASH.dbN or BASE+gitCOUNT.HASH
        local base=$(echo "$version" | sed -E 's/\+git.*//')
        local commit_count=$(echo "$version" | grep -oP '\+git\K[0-9]+' || echo "")
        local commit_hash=$(echo "$version" | grep -oP '\+git[0-9]+\.\K[a-f0-9]{8}' || echo "")
        local db_suffix=$(echo "$version" | grep -oP '\.db\K[0-9]+$' || echo "1")

        echo "base=$base"
        echo "commit_count=$commit_count"
        echo "commit_hash=$commit_hash"
        echo "db_suffix=$db_suffix"
    else
        # Format: VERSION.dbN or VERSION
        local base=$(echo "$version" | sed -E 's/\.?db[0-9]+$//')
        local db_suffix=$(echo "$version" | grep -oP '\.?db\K[0-9]+$' || echo "1")

        echo "base=$base"
        echo "db_suffix=$db_suffix"
    fi
}

# Strip all db suffixes from version string
strip_db_suffixes() {
    local version="$1"
    echo "$version" | sed -E 's/(\.?db[0-9]+)+$//'
}

# Extract commit hash from git or pinned version
extract_commit_hash() {
    local version="$1"
    echo "$version" | grep -oP '\+(git|pin)[0-9]+\.\K[a-f0-9]{8}' | head -c 8 || echo ""
}

# Extract base version (strip git and db suffixes)
extract_base_version() {
    local version="$1"
    local type="$2"

    if [[ "$type" == "git" ]]; then
        echo "$version" | sed -E 's/\+git.*//'
    else
        echo "$version" | sed -E 's/\.?db[0-9]+$//'
    fi
}

# Extract db suffix number
extract_db_suffix() {
    local version="$1"

    local db_num=$(echo "$version" | grep -oP '\.?db\K[0-9]+$' || echo "")
    if [[ -n "$db_num" ]]; then
        echo "$db_num"
    else
        echo "1"
    fi
}

# Increment db suffix
increment_db_version() {
    local version="$1"
    local new_db="$2"
    local base=$(strip_db_suffixes "$version")
    echo "${base}.db${new_db}"
}

# Compare git versions by commit hash (ignores db suffix)
compare_git_versions() {
    local version1="$1"
    local version2="$2"

    local hash1=$(extract_commit_hash "$version1")
    local hash2=$(extract_commit_hash "$version2")

    if [[ -z "$hash1" || -z "$hash2" ]]; then
        log_error "Failed to extract commit hashes for comparison"
        log_error "  Version 1: $version1 -> hash: $hash1"
        log_error "  Version 2: $version2 -> hash: $hash2"
        return 1
    fi

    if [[ "$hash1" == "$hash2" ]]; then
        echo "equal"
    else
        echo "different"
    fi
}

# Compare stable versions (ignores db suffix)
compare_stable_versions() {
    local version1="$1"
    local version2="$2"

    local base1=$(strip_db_suffixes "$version1")
    local base2=$(strip_db_suffixes "$version2")

    if [[ "$base1" == "$base2" ]]; then
        echo "equal"
    else
        echo "different"
    fi
}

# Build git version string from components
build_git_version() {
    local base="$1"
    local commit_count="$2"
    local commit_hash="$3"
    local db_suffix="${4:-1}"

    echo "${base}+git${commit_count}.${commit_hash}.db${db_suffix}"
}

# Build stable version string
build_stable_version() {
    local base="$1"
    local db_suffix="${2:-1}"

    echo "${base}.db${db_suffix}"
}

# Validate git version format
validate_git_version() {
    local version="$1"

    # Check format: BASE+gitCOUNT.HASH[.dbN]
    if ! echo "$version" | grep -qP '^[0-9.]+\+git[0-9]+\.[a-f0-9]{8}(\.db[0-9]+)?$'; then
        log_error "Invalid git version format: $version"
        log_error "  Expected format: BASE+gitCOUNT.HASH[.dbN]"
        log_error "  Example: 25.11+git2576.7c089857.db1"
        return 1
    fi

    return 0
}

# Validate stable version format
validate_stable_version() {
    local version="$1"

    # Check format: VERSION[.dbN]
    if ! echo "$version" | grep -qP '^[0-9.]+[a-z0-9_-]*(\.db[0-9]+)?$'; then
        log_error "Invalid stable version format: $version"
        log_error "  Expected format: VERSION[.dbN]"
        log_error "  Example: 0.8.db1 or 1.2.3.db2"
        return 1
    fi

    return 0
}

# Determine version type from format
detect_version_type() {
    local version="$1"

    if echo "$version" | grep -qP '\+git[0-9]+\.[a-f0-9]{8}'; then
        echo "git"
    else
        echo "stable"
    fi
}

# Normalize version for comparison (strip db, normalize format)
normalize_version() {
    local version="$1"

    strip_db_suffixes "$version"
}

# Check if version needs update
# Returns: 0 if update needed, 1 if not
version_needs_update() {
    local current="$1"
    local upstream="$2"
    local type="$3"

    local current_clean=$(normalize_version "$current")
    local upstream_clean=$(normalize_version "$upstream")

    if [[ "$type" == "git" ]]; then
        local result=$(compare_git_versions "$current_clean" "$upstream_clean")
        if [[ "$result" == "different" ]]; then
            return 0  # Update needed
        else
            return 1  # No update needed
        fi
    else
        local result=$(compare_stable_versions "$current_clean" "$upstream_clean")
        if [[ "$result" == "different" ]]; then
            return 0  # Update needed
        else
            return 1  # No update needed
        fi
    fi
}

# Get next db number for rebuild
get_next_db_number() {
    local version="$1"

    local current_db=$(extract_db_suffix "$version")
    echo $((current_db + 1))
}

# Pretty print version comparison
print_version_comparison() {
    local current="$1"
    local upstream="$2"
    local type="${3:-auto}"

    if [[ "$type" == "auto" ]]; then
        type=$(detect_version_type "$upstream")
    fi

    log_info "Version comparison:"
    log_info "  Current:  $current"
    log_info "  Upstream: $upstream"

    if [[ "$type" == "git" ]]; then
        local current_hash=$(extract_commit_hash "$current")
        local upstream_hash=$(extract_commit_hash "$upstream")
        log_info "  Current hash:  $current_hash"
        log_info "  Upstream hash: $upstream_hash"

        if [[ "$current_hash" != "$upstream_hash" ]]; then
            log_info "  Status: UPDATE NEEDED (hashes differ)"
        else
            log_info "  Status: UP TO DATE (hashes match)"
        fi
    else
        local current_base=$(strip_db_suffixes "$current")
        local upstream_base=$(strip_db_suffixes "$upstream")

        if [[ "$current_base" != "$upstream_base" ]]; then
            log_info "  Status: UPDATE NEEDED (versions differ)"
        else
            log_info "  Status: UP TO DATE (versions match)"
        fi
    fi
}

# Module initialization flag
readonly VERSION_LOADED=true
