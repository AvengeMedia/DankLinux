#!/bin/bash
# PPA update detection - checks upstream repos against debian/changelog versions
# Outputs space-separated list of packages needing updates to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UBUNTU_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

UPDATED_PACKAGES=()

# Package definitions: "name:repo:type" (type: git or release)
PACKAGES=(
    "niri-git:YaLTeR/niri:git"
    "quickshell-git:quickshell-mirror/quickshell:git"
    "niri:YaLTeR/niri:release"
    "cliphist:sentriz/cliphist:release"
    "matugen:InioX/matugen:release"
    "danksearch:AvengeMedia/danksearch:release"
    "dgop:AvengeMedia/dgop:release"
)

get_latest_tag() {
    local repo="$1"
    local tag
    tag=$(curl -sf "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | \
        jq -r '.tag_name // empty' 2>/dev/null || echo "")
    
    if [ -n "$tag" ]; then
        echo "${tag#v}"
        return
    fi
    
    tag=$(curl -sf "https://api.github.com/repos/$repo/tags" 2>/dev/null | \
        jq -r '.[0].name // empty' 2>/dev/null || echo "")
    echo "${tag#v}"
}

get_latest_commit() {
    local repo="$1"
    local branch="${2:-main}"
    local commit_data
    commit_data=$(curl -sf "https://api.github.com/repos/$repo/commits/$branch" 2>/dev/null || \
                  curl -sf "https://api.github.com/repos/$repo/commits/master" 2>/dev/null || echo "")
    
    if [ -z "$commit_data" ]; then
        echo ""
        return
    fi
    
    local commit_hash
    commit_hash=$(echo "$commit_data" | jq -r '.sha // empty' 2>/dev/null)
    [ -n "$commit_hash" ] && echo "${commit_hash:0:8}"
}

get_changelog_version() {
    local changelog="$1/debian/changelog"
    [ ! -f "$changelog" ] && return
    head -1 "$changelog" | sed -n 's/^[^ ]* (\([^)]*\)).*/\1/p'
}

# Extract commit hash from git version: "25.08+git2540.012700ddppa1" -> "012700dd"
extract_git_commit() {
    echo "$1" | sed -n 's/.*+git[0-9]*\.\([a-f0-9]*\)ppa.*/\1/p'
}

# Extract base version: "0.7.0ppa10" or "0.7.0-1ppa10" -> "0.7.0"
extract_release_version() {
    echo "$1" | sed 's/ppa[0-9]*$//' | sed 's/-[0-9]*$//'
}

info "🔍 Checking for PPA package updates..."
echo "" >&2

for pkg_info in "${PACKAGES[@]}"; do
    IFS=':' read -r package repo type <<< "$pkg_info"
    package_dir="$UBUNTU_DIR/$package"
    
    info "📦 Checking $package..."
    
    if [ ! -d "$package_dir/debian" ]; then
        warn "   Skipping $package (no debian packaging)"
        echo "" >&2
        continue
    fi
    
    current_version=$(get_changelog_version "$package_dir")
    if [ -z "$current_version" ]; then
        warn "   Could not read version from changelog"
        echo "" >&2
        continue
    fi
    
    if [ "$type" = "git" ]; then
        current_commit=$(extract_git_commit "$current_version")
        info "   Current: $current_version (commit: ${current_commit:-unknown})"
        
        latest_commit=$(get_latest_commit "$repo")
        if [ -z "$latest_commit" ]; then
            warn "   Could not fetch latest commit from $repo"
            echo "" >&2
            continue
        fi
        
        info "   Latest commit: $latest_commit"
        
        if [ "${current_commit:0:8}" != "${latest_commit:0:8}" ]; then
            success "   ✨ Update available: ${current_commit:-none} → $latest_commit"
            UPDATED_PACKAGES+=("$package")
        else
            info "   ✓ Already up to date"
        fi
    else
        current_base=$(extract_release_version "$current_version")
        info "   Current: $current_version (base: $current_base)"
        
        latest_tag=$(get_latest_tag "$repo")
        if [ -z "$latest_tag" ]; then
            warn "   Could not fetch latest tag from $repo"
            echo "" >&2
            continue
        fi
        
        info "   Latest release: $latest_tag"
        
        if [ "$current_base" != "$latest_tag" ]; then
            success "   ✨ Update available: $current_base → $latest_tag"
            UPDATED_PACKAGES+=("$package")
        else
            info "   ✓ Already up to date"
        fi
    fi
    
    echo "" >&2
done

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ${#UPDATED_PACKAGES[@]} -gt 0 ]; then
    success "Found ${#UPDATED_PACKAGES[@]} package(s) with updates:"
    for pkg in "${UPDATED_PACKAGES[@]}"; do
        info "   • $pkg"
    done
    echo "" >&2
    echo "${UPDATED_PACKAGES[*]}"
else
    info "✓ All packages are up to date"
    echo ""
fi
