#!/bin/bash
# Hash verification utilities
# Ensures source integrity matches upstream commit/release

# Source guard to prevent multiple sourcing
if [[ -n "${_OBS_HASH_SOURCED:-}" ]]; then
    return 0
fi
readonly _OBS_HASH_SOURCED=1

# Source dependencies
_HASH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$_HASH_LIB_DIR/common.sh"
# shellcheck source=./version.sh
source "$_HASH_LIB_DIR/version.sh"
# shellcheck source=./api.sh
source "$_HASH_LIB_DIR/api.sh"

# Verify git source matches upstream commit
# Returns: 0 if hash matches, 1 if mismatch
verify_git_source_hash() {
    local package="$1"
    local expected_hash="$2"  # 8-char short hash
    local source_dir="$3"

    # Ensure expected hash is 8 chars
    expected_hash="${expected_hash:0:8}"

    log_debug "Verifying git source hash for $package"
    log_debug "  Expected: $expected_hash"
    log_debug "  Source dir: $source_dir"

    # Check if source directory is a git repo
    if [[ ! -d "$source_dir/.git" ]]; then
        log_warn "Source directory is not a git repo, skipping hash verification"
        return 0
    fi

    # Get actual commit hash from cloned source
    local actual_hash=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null | head -c 8)

    if [[ -z "$actual_hash" ]]; then
        log_error "Failed to get commit hash from source directory"
        return 1
    fi

    log_debug "  Actual: $actual_hash"

    if [[ "$actual_hash" == "$expected_hash" ]]; then
        log_success "Hash verified: $actual_hash matches expected $expected_hash"
        return 0
    else
        log_error "Hash mismatch for $package"
        log_error "  Expected (upstream): $expected_hash"
        log_error "  Actual (downloaded): $actual_hash"
        log_error ""
        log_error "This indicates the source download was corrupted or tampered with."
        log_error "Please retry the build."
        return 1
    fi
}

# Verify release tarball checksum
# Returns: 0 if checksum matches, 1 if mismatch or unavailable
verify_release_checksum() {
    local package="$1"
    local tarball="$2"
    local upstream_repo="$3"
    local version="$4"

    log_debug "Verifying release checksum for $package version $version"

    # Try to get checksum file URL from release
    local checksum_url=$(get_release_checksum_url "$upstream_repo" "$version" 2>/dev/null)

    if [[ -z "$checksum_url" ]]; then
        log_warn "No checksum file found for $package $version, skipping verification"
        return 0
    fi

    log_debug "Downloading checksum file: $checksum_url"

    # Download checksum file
    local checksum_file=$(mktemp)
    if ! curl -sL "$checksum_url" -o "$checksum_file"; then
        log_warn "Failed to download checksum file, skipping verification"
        rm -f "$checksum_file"
        return 0
    fi

    # Extract expected checksum for this tarball
    local tarball_name=$(basename "$tarball")
    local expected_sum=$(grep "$tarball_name" "$checksum_file" 2>/dev/null | awk '{print $1}')

    if [[ -z "$expected_sum" ]]; then
        log_warn "Checksum for $tarball_name not found in checksum file, skipping verification"
        rm -f "$checksum_file"
        return 0
    fi

    # Calculate actual checksum
    local actual_sum=$(sha256sum "$tarball" | awk '{print $1}')

    rm -f "$checksum_file"

    if [[ "$expected_sum" == "$actual_sum" ]]; then
        log_success "Checksum verified for $tarball_name"
        log_debug "  SHA256: $actual_sum"
        return 0
    else
        log_error "Checksum mismatch for $tarball_name"
        log_error "  Expected: $expected_sum"
        log_error "  Actual:   $actual_sum"
        log_error ""
        log_error "This indicates the download was corrupted or the release was modified."
        log_error "Please retry the build or report this issue."
        return 1
    fi
}

# Verify hash persists across rebuilds
# Returns: 0 if hash matches version, 1 if mismatch
verify_rebuild_hash_integrity() {
    local package="$1"
    local version="$2"  # Version with db suffix
    local source_dir="$3"

    log_debug "Verifying rebuild hash integrity for $package"

    # Strip db suffix to get base version
    local base_version=$(strip_db_suffixes "$version")

    # Extract expected hash from version
    local expected_hash=$(extract_commit_hash "$base_version")

    if [[ -z "$expected_hash" ]]; then
        log_warn "No hash found in version string, skipping rebuild integrity check"
        log_debug "Version: $version"
        return 0
    fi

    # Verify source matches expected hash
    verify_git_source_hash "$package" "$expected_hash" "$source_dir"
}

# Calculate tarball checksum
# Returns: SHA256 checksum
calculate_tarball_checksum() {
    local tarball="$1"

    if [[ ! -f "$tarball" ]]; then
        log_error "Tarball not found: $tarball"
        return 1
    fi

    sha256sum "$tarball" | awk '{print $1}'
}

# Verify tarball integrity (check it's not corrupted)
# Returns: 0 if valid, 1 if corrupted
verify_tarball_integrity() {
    local tarball="$1"

    log_debug "Verifying tarball integrity: $(basename "$tarball")"

    local compression=$(file -b "$tarball" | grep -oP '(gzip|XZ|bzip2)' | head -1 | tr '[:upper:]' '[:lower:]')

    case "$compression" in
        gzip)
            if gzip -t "$tarball" 2>/dev/null; then
                log_debug "Gzip tarball integrity OK"
                return 0
            else
                log_error "Gzip tarball is corrupted"
                return 1
            fi
            ;;
        xz)
            if xz -t "$tarball" 2>/dev/null; then
                log_debug "XZ tarball integrity OK"
                return 0
            else
                log_error "XZ tarball is corrupted"
                return 1
            fi
            ;;
        bzip2)
            if bzip2 -t "$tarball" 2>/dev/null; then
                log_debug "Bzip2 tarball integrity OK"
                return 0
            else
                log_error "Bzip2 tarball is corrupted"
                return 1
            fi
            ;;
        *)
            # Assume uncompressed tar
            if tar -tf "$tarball" &>/dev/null; then
                log_debug "Uncompressed tarball integrity OK"
                return 0
            else
                log_error "Tarball is corrupted or invalid format"
                return 1
            fi
            ;;
    esac
}

# Create checksum file for tarball
# Creates: /tmp/package.tar.gz.sha256
create_checksum_file() {
    local tarball="$1"
    local checksum_file="${tarball}.sha256"

    local checksum=$(calculate_tarball_checksum "$tarball")

    if [[ -z "$checksum" ]]; then
        log_error "Failed to calculate checksum for $tarball"
        return 1
    fi

    echo "$checksum  $(basename "$tarball")" > "$checksum_file"

    log_debug "Created checksum file: $checksum_file"
    log_debug "  SHA256: $checksum"

    echo "$checksum_file"
}

# Verify two tarballs have identical content (for rebuild verification)
# Returns: 0 if equivalent, 1 if different
verify_tarball_equivalence() {
    local tarball1="$1"
    local tarball2="$2"

    local sum1=$(calculate_tarball_checksum "$tarball1")
    local sum2=$(calculate_tarball_checksum "$tarball2")

    if [[ "$sum1" == "$sum2" ]]; then
        log_success "Tarballs are identical"
        log_debug "  SHA256: $sum1"
        return 0
    else
        log_error "Tarballs differ"
        log_error "  $(basename "$tarball1"): $sum1"
        log_error "  $(basename "$tarball2"): $sum2"
        return 1
    fi
}

# Verify commit hash against upstream
# Returns: 0 if hash exists in upstream, 1 if not found
verify_upstream_commit() {
    local repo="$1"
    local commit_hash="$2"
    local branch="${3:-main}"

    log_debug "Verifying commit $commit_hash exists in upstream $repo@$branch"

    # Get latest commit from upstream
    local latest_commit=$(get_latest_commit "$repo" "$branch")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch latest commit from upstream"
        return 1
    fi

    # If hashes match, commit exists (and is latest)
    if [[ "$latest_commit" == "$commit_hash" ]]; then
        log_debug "Commit hash matches latest upstream commit"
        return 0
    fi

    # Check if commit exists in repo using API
    local response=$(api_call_with_retry "https://api.github.com/repos/$repo/commits/$commit_hash" "GET" 2>/dev/null)

    if [[ $? -eq 0 && -n "$response" ]]; then
        log_debug "Commit hash found in upstream (not latest)"
        return 0
    else
        log_error "Commit hash $commit_hash not found in upstream $repo"
        return 1
    fi
}

# Generate build metadata file with hashes
# Creates: /tmp/build-metadata.json
generate_build_metadata() {
    local package="$1"
    local version="$2"
    local source_dir="$3"
    local tarball="$4"

    local metadata_file="/tmp/${package}-build-metadata.json"

    local source_commit=""
    if [[ -d "$source_dir/.git" ]]; then
        source_commit=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null)
    fi

    local tarball_checksum=""
    if [[ -f "$tarball" ]]; then
        tarball_checksum=$(calculate_tarball_checksum "$tarball")
    fi

    cat > "$metadata_file" <<EOF
{
  "package": "$package",
  "version": "$version",
  "build_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "source_commit": "$source_commit",
  "tarball_checksum": "$tarball_checksum",
  "builder": "obs-automation-v2"
}
EOF

    log_debug "Generated build metadata: $metadata_file"
    echo "$metadata_file"
}

# Module initialization flag
readonly HASH_LOADED=true
