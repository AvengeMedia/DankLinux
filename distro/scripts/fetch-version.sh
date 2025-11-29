#!/usr/bin/env bash
# Fetches latest version information from GitHub
# Usage: ./fetch-version.sh <repo> [type]

set -euo pipefail

REPO="$1"
TYPE="${2:-release}"  # release or commit

# Helper to fetch with retries and token
gh_curl() {
    local url="$1"
    local retries=3
    local count=0
    local response
    
    while [ $count -lt $retries ]; do
        if [ -n "${GITHUB_TOKEN:-}" ]; then
            response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$url")
        else
            response=$(curl -s "$url")
        fi
        
        if [ -n "$response" ] && echo "$response" | jq -e . >/dev/null 2>&1; then
            if echo "$response" | jq -e '.message // empty' | grep -q "API rate limit exceeded"; then
                echo "Error: GitHub API rate limit exceeded" >&2
                return 1
            fi
            echo "$response"
            return 0
        fi
        
        count=$((count + 1))
        [ $count -lt $retries ] && sleep 2
    done
    
    echo "Error: Failed to fetch $url after $retries attempts" >&2
    return 1
}

if [[ "$TYPE" == "release" ]]; then
    # Fetch latest release tag (try releases API first, fall back to tags)
    DATA=$(gh_curl "https://api.github.com/repos/${REPO}/releases/latest") || exit 1
    RELEASE_TAG=$(echo "$DATA" | jq -r '.tag_name // empty')

    # If no releases (or not found in latest), try tags endpoint
    if [[ -z "$RELEASE_TAG" ]] || [[ "$RELEASE_TAG" == "null" ]]; then
        DATA=$(gh_curl "https://api.github.com/repos/${REPO}/tags") || exit 1
        echo "$DATA" | jq -r '.[0].name // empty'
    else
        echo "$RELEASE_TAG"
    fi
elif [[ "$TYPE" == "commit" ]]; then
    # Fetch latest commit info
    COMMIT_DATA=$(gh_curl "https://api.github.com/repos/${REPO}/commits/master") || exit 1

    # Extract commit hash
    COMMIT=$(echo "$COMMIT_DATA" | jq -r '.sha // empty')
    SHORT_COMMIT="${COMMIT:0:7}"

    # Extract commit date in YYYYMMDD format
    COMMIT_DATE=$(echo "$COMMIT_DATA" | jq -r '.commit.committer.date // empty')
    SNAPDATE=$(date -d "$COMMIT_DATE" +%Y%m%d 2>/dev/null || echo "")

    if [[ -z "$COMMIT" ]] || [[ "$COMMIT" == "null" ]]; then
        echo "Error: Could not fetch commit info for $REPO" >&2
        exit 1
    fi
        
    echo "${COMMIT}|${SHORT_COMMIT}|${SNAPDATE}"
else
    echo "Error: Unknown type $TYPE" >&2
    exit 1
fi
