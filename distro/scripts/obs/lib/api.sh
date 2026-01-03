#!/bin/bash
# API interaction layer for GitHub and OBS
# Includes retry logic, rate limit handling, and response caching

# Source guard to prevent multiple sourcing
if [[ -n "${_OBS_API_SOURCED:-}" ]]; then
    return 0
fi
readonly _OBS_API_SOURCED=1

# Source dependencies
_API_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$_API_LIB_DIR/common.sh"

# GitHub API base URL
readonly GITHUB_API="https://api.github.com"

# Retry configuration (can be overridden by defaults in config)
RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-3}"
RETRY_BACKOFF=(2 4 8)

# Generic API call with retry and exponential backoff
api_call_with_retry() {
    local url="$1"
    local method="${2:-GET}"
    local max_attempts="${3:-$RETRY_ATTEMPTS}"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "API call attempt $attempt/$max_attempts: $method $url"

        local response
        local http_code

        # Build curl command with optional GitHub token
        local curl_cmd="curl -sL -w '\n%{http_code}' -X $method"

        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            curl_cmd="$curl_cmd -H 'Authorization: token $GITHUB_TOKEN'"
        fi

        curl_cmd="$curl_cmd -H 'Accept: application/vnd.github.v3+json' '$url'"

        # Execute curl command
        response=$(eval "$curl_cmd" 2>&1)

        http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | sed '$d')

        # Success (2xx)
        if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
            echo "$body"
            return 0
        fi

        # Rate limit hit (403 or 429)
        if [[ "$http_code" == "403" || "$http_code" == "429" ]]; then
            local retry_after=$(echo "$body" | grep -i "retry-after" | grep -oP '\d+' || echo "")
            local wait_time="${retry_after:-${RETRY_BACKOFF[$((attempt-1))]}}"

            log_warn "Rate limit hit (HTTP $http_code), waiting $wait_time seconds..."
            sleep "$wait_time"

        # Server error (5xx)
        elif [[ "$http_code" =~ ^5[0-9]{2}$ ]]; then
            local wait_time="${RETRY_BACKOFF[$((attempt-1))]}"
            log_warn "Server error (HTTP $http_code), retrying in $wait_time seconds..."
            sleep "$wait_time"

        # Client error (4xx) - don't retry
        else
            log_error "API call failed with HTTP $http_code"
            log_debug "Response: $body"
            return 1
        fi

        attempt=$((attempt + 1))
    done

    log_error "API call failed after $max_attempts attempts"
    return 1
}

# Get latest commit from GitHub repository
# Returns: 8-char short commit hash
get_latest_commit() {
    local repo="$1"
    local branch="${2:-main}"

    # Check cache first
    local cache_key="${repo//\//_}_${branch}_commit"
    local cached=$(get_cache "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        log_debug "Using cached commit for $repo@$branch: $cached"
        echo "$cached"
        return 0
    fi

    # Try main branch first, fall back to master
    local response=$(api_call_with_retry "$GITHUB_API/repos/$repo/commits/$branch" "GET" 2>/dev/null)

    if [[ $? -ne 0 || -z "$response" ]]; then
        log_debug "Branch '$branch' not found, trying 'master'..."
        response=$(api_call_with_retry "$GITHUB_API/repos/$repo/commits/master" "GET")

        if [[ $? -ne 0 ]]; then
            log_error "Failed to fetch latest commit for $repo"
            return 1
        fi
    fi

    # Extract commit SHA and take first 8 chars
    local commit_hash=$(echo "$response" | grep -m1 '"sha"' | grep -oP ':\s*"\K[a-f0-9]{40}' | head -c 8)

    if [[ -z "$commit_hash" ]]; then
        log_error "Failed to parse commit hash from API response"
        return 1
    fi

    # Cache the result
    set_cache "$cache_key" "$commit_hash"

    echo "$commit_hash"
}

# Get commit count from GitHub repository
# Returns: Total commit count
get_commit_count() {
    local repo="$1"
    local branch="${2:-main}"

    # Check cache first
    local cache_key="${repo//\//_}_${branch}_count"
    local cached=$(get_cache "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        log_debug "Using cached commit count for $repo@$branch: $cached"
        echo "$cached"
        return 0
    fi

    # Try to get count via API pagination (faster than cloning)
    local response=$(curl -sI -H "Accept: application/vnd.github.v3+json" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "$GITHUB_API/repos/$repo/commits?per_page=1&sha=$branch" 2>/dev/null)

    local count=$(echo "$response" | grep -i "^link:" | sed -n 's/.*page=\([0-9]*\)>; rel="last".*/\1/p')

    # If API pagination doesn't work, fall back to git clone
    if [[ -z "$count" || "$count" == "0" ]]; then
        log_debug "API pagination failed, falling back to git clone for commit count"

        local temp_dir=$(mktemp -d)
        if git clone --quiet --bare "https://github.com/$repo.git" "$temp_dir/repo" 2>/dev/null; then
            count=$(git -C "$temp_dir/repo" rev-list --count HEAD 2>/dev/null || echo "9999")
            rm -rf "$temp_dir"
        else
            log_warn "Failed to clone repo for commit count, using fallback value"
            rm -rf "$temp_dir"
            count="9999"
        fi
    fi

    # Cache the result
    set_cache "$cache_key" "$count"

    echo "$count"
}

# Get latest release tag from GitHub
# Returns: Version string (without 'v' prefix)
get_latest_release() {
    local repo="$1"

    # Check cache first
    local cache_key="${repo//\//_}_release"
    local cached=$(get_cache "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        log_debug "Using cached release for $repo: $cached"
        echo "$cached"
        return 0
    fi

    local response=$(api_call_with_retry "$GITHUB_API/repos/$repo/releases/latest" "GET")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch latest release for $repo"
        return 1
    fi

    # Extract tag_name and strip 'v' prefix
    local tag=$(echo "$response" | grep -m1 '"tag_name"' | grep -oP ':\s*"\K[^"]+')
    local version="${tag#v}"

    if [[ -z "$version" ]]; then
        log_error "Failed to parse release tag from API response"
        return 1
    fi

    # Cache the result
    set_cache "$cache_key" "$version"

    echo "$version"
}

# Get latest git tag from GitHub
# Returns: Version string (without 'v' prefix)
get_latest_tag() {
    local repo="$1"

    # Check cache first
    local cache_key="${repo//\//_}_tag"
    local cached=$(get_cache "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        log_debug "Using cached tag for $repo: $cached"
        echo "$cached"
        return 0
    fi

    local response=$(api_call_with_retry "$GITHUB_API/repos/$repo/tags" "GET")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to fetch tags for $repo"
        return 1
    fi

    # Extract first tag name and strip 'v' prefix
    local tag=$(echo "$response" | grep -m1 '"name"' | grep -oP ':\s*"\K[^"]+')
    local version="${tag#v}"

    if [[ -z "$version" ]]; then
        log_error "Failed to parse tag from API response"
        return 1
    fi

    # Cache the result
    set_cache "$cache_key" "$version"

    echo "$version"
}

# Get OBS package version via API
# Returns: Version string from spec file
get_obs_version() {
    local package="$1"
    local project="${OBS_PROJECT:-home:AvengeMedia:danklinux}"

    # Check cache first
    local cache_key="obs_${project//[:\/ ]/_}_${package}_version"
    local cached=$(get_cache "$cache_key" 2>/dev/null || echo "")

    if [[ -n "$cached" ]]; then
        log_debug "Using cached OBS version for $package: $cached"
        echo "$cached"
        return 0
    fi

    # Check if osc command is available
    if ! command -v osc &> /dev/null; then
        log_error "osc command not found, skipping OBS version check"
        return 1
    fi

    # Try .spec file first (OpenSUSE packages)
    local spec_content=$(osc api "/source/$project/$package/${package}.spec" 2>/dev/null)
    local version=""

    if [[ $? -eq 0 && -n "$spec_content" ]]; then
        # Extract Version: field from spec file
        version=$(echo "$spec_content" | grep -m1 "^Version:" | awk '{print $2}' | tr -d ' ')
    else
        # Try .dsc file (Debian-only packages like ghostty, niri stable)
        log_debug "No .spec file found, trying .dsc file for $package"
        local dsc_content=$(osc api "/source/$project/$package/${package}.dsc" 2>/dev/null)

        if [[ $? -ne 0 || -z "$dsc_content" ]]; then
            # .dsc file with exact package name not found, try to find versioned .dsc
            log_debug "No ${package}.dsc found, searching for versioned .dsc file"
            local dsc_file=$(osc api "/source/$project/$package" 2>/dev/null | grep -o 'name="[^"]*\.dsc"' | head -1 | cut -d'"' -f2)

            if [[ -z "$dsc_file" ]]; then
                log_debug "Package $package not found on OBS (new package)"
                return 1
            fi

            log_debug "Found .dsc file: $dsc_file"
            dsc_content=$(osc api "/source/$project/$package/$dsc_file" 2>/dev/null)

            if [[ $? -ne 0 || -z "$dsc_content" ]]; then
                log_debug "Failed to fetch $dsc_file"
                return 1
            fi
        fi

        # Extract Version: field from .dsc file
        version=$(echo "$dsc_content" | grep -m1 "^Version:" | awk '{print $2}' | tr -d ' ')
    fi

    if [[ -z "$version" ]]; then
        log_error "Failed to parse version from OBS package files"
        return 1
    fi

    # Cache the result
    set_cache "$cache_key" "$version"

    echo "$version"
}

# Check if package exists on OBS
# Returns: 0 if exists, 1 if not
obs_package_exists() {
    local package="$1"
    local project="${OBS_PROJECT:-home:AvengeMedia:danklinux}"

    if ! command -v osc &> /dev/null; then
        log_warn "osc command not found, cannot check OBS package existence"
        return 1
    fi

    local response=$(osc api "/source/$project/$package" 2>/dev/null)

    if [[ $? -eq 0 && -n "$response" && "$response" != *"<error"* ]]; then
        return 0
    else
        return 1
    fi
}

# Get release asset download URL
# Returns: Download URL for matching asset
get_release_asset_url() {
    local repo="$1"
    local version="$2"
    local pattern="$3"

    local tag="v${version}"
    local response=$(api_call_with_retry "$GITHUB_API/repos/$repo/releases/tags/$tag" "GET")

    if [[ $? -ne 0 ]]; then
        # Try without 'v' prefix
        tag="$version"
        response=$(api_call_with_retry "$GITHUB_API/repos/$repo/releases/tags/$tag" "GET")

        if [[ $? -ne 0 ]]; then
            log_error "Failed to fetch release $version for $repo"
            return 1
        fi
    fi

    # Extract browser_download_url for matching asset
    local url=$(echo "$response" | grep -A2 '"name"' | grep -B1 "$pattern" | grep '"browser_download_url"' | grep -oP ':\s*"\K[^"]+' | head -1)

    if [[ -z "$url" ]]; then
        log_error "No asset matching pattern '$pattern' found in release $version"
        return 1
    fi

    echo "$url"
}

# Get release checksum file URL
# Returns: URL to SHA256SUMS or similar file
get_release_checksum_url() {
    local repo="$1"
    local version="$2"

    local tag="v${version}"
    local response=$(api_call_with_retry "$GITHUB_API/repos/$repo/releases/tags/$tag" "GET")

    if [[ $? -ne 0 ]]; then
        tag="$version"
        response=$(api_call_with_retry "$GITHUB_API/repos/$repo/releases/tags/$tag" "GET")

        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    # Look for SHA256SUMS, checksums.txt, or similar
    local url=$(echo "$response" | grep '"browser_download_url"' | grep -i -E "(SHA256|checksum)" | grep -oP ':\s*"\K[^"]+' | head -1)

    echo "$url"
}

# Download file with retry
download_file_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts="${3:-$RETRY_ATTEMPTS}"

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Download attempt $attempt/$max_attempts: $url"

        if curl -L -f -o "$output" "$url" 2>/dev/null; then
            log_debug "Download successful: $(basename "$output")"
            return 0
        fi

        local wait_time="${RETRY_BACKOFF[$((attempt-1))]}"
        log_warn "Download failed, retrying in $wait_time seconds..."
        sleep "$wait_time"

        attempt=$((attempt + 1))
    done

    log_error "Download failed after $max_attempts attempts: $url"
    return 1
}

# Clear API cache for a specific package
clear_package_cache() {
    local package="$1"

    if [[ -d "$CACHE_DIR" ]]; then
        find "$CACHE_DIR" -name "*${package}*" -delete 2>/dev/null || true
        log_debug "Cleared cache for package: $package"
    fi
}

# Get GitHub API rate limit status
get_rate_limit_status() {
    local response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN:-}" \
        "$GITHUB_API/rate_limit" 2>/dev/null)

    if [[ $? -eq 0 && -n "$response" ]]; then
        local remaining=$(echo "$response" | grep -m1 '"remaining"' | grep -oP ':\s*\K[0-9]+')
        local limit=$(echo "$response" | grep -m1 '"limit"' | grep -oP ':\s*\K[0-9]+')
        local reset=$(echo "$response" | grep -m1 '"reset"' | grep -oP ':\s*\K[0-9]+')

        echo "Rate limit: $remaining/$limit (resets at $(date -d @$reset))"
    else
        echo "Unable to fetch rate limit status"
    fi
}

# Module initialization flag
readonly API_LOADED=true
