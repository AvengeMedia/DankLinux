#!/usr/bin/env bash
# Fetches latest version information from GitHub
set -euo pipefail

REPO="$1"
TYPE="${2:-release}"  # release or commit

if [[ "$TYPE" == "release" ]]; then
    # Fetch latest release tag (try releases API first, fall back to tags)
    RELEASE_TAG=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | \
        jq -r '.tag_name // empty')

    # If no releases, try tags endpoint
    if [[ -z "$RELEASE_TAG" ]]; then
        curl -s "https://api.github.com/repos/${REPO}/tags" | \
            jq -r '.[0].name // empty'
    else
        echo "$RELEASE_TAG"
    fi
elif [[ "$TYPE" == "commit" ]]; then
    # Fetch latest commit info
    COMMIT_DATA=$(curl -s "https://api.github.com/repos/${REPO}/commits/master")

    # Extract commit hash
    COMMIT=$(echo "$COMMIT_DATA" | jq -r '.sha // empty')
    SHORT_COMMIT="${COMMIT:0:7}"

    # Extract commit date in YYYYMMDD format
    COMMIT_DATE=$(echo "$COMMIT_DATA" | jq -r '.commit.committer.date // empty')
    SNAPDATE=$(date -d "$COMMIT_DATE" +%Y%m%d 2>/dev/null || echo "")

    # Try to get commit count (this requires cloning or using additional API calls)
    # For now, we'll estimate or require manual update
    echo "${COMMIT}|${SHORT_COMMIT}|${SNAPDATE}"
else
    echo "Error: Unknown type $TYPE" >&2
    exit 1
fi
