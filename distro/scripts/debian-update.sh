#!/bin/bash
# Debian package update checker and changelog updater
# Usage: ./debian-check.sh [--update] [base-directory]
#
# Modes:
#   ./debian-check.sh                         # Check only (PPA default: distro/ubuntu)
#   ./debian-check.sh distro/debian           # Check only (OBS)
#   ./debian-check.sh --update distro/debian  # Check and update changelogs
#
# Outputs space-separated list of packages needing/receiving updates to stdout

set -euo pipefail

UPDATE_MODE=false
BASE_DIR=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --update) UPDATE_MODE=true ;;
        *) BASE_DIR="$arg" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default base directory
if [ -z "$BASE_DIR" ]; then
    BASE_DIR="distro/ubuntu"
fi
BASE_DIR="$REPO_ROOT/$BASE_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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

get_git_info() {
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
    
    # Get commit count via API pagination
    local commit_count
    commit_count=$(curl -sI "https://api.github.com/repos/$repo/commits?per_page=1" 2>/dev/null | \
        grep -i 'link:' | sed 's/.*page=\([0-9]*\)>; rel="last".*/\1/' || echo "")
    
    if [ -z "$commit_count" ]; then
        local temp_dir
        temp_dir=$(mktemp -d)
        if git clone --quiet "https://github.com/$repo.git" "$temp_dir" 2>/dev/null; then
            commit_count=$(cd "$temp_dir" && git rev-list --count HEAD)
            rm -rf "$temp_dir"
        else
            commit_count="9999"
            rm -rf "$temp_dir"
        fi
    fi
    
    local latest_tag
    latest_tag=$(get_latest_tag "$repo")
    
    echo "${commit_hash:0:8}:$commit_count:$latest_tag"
}

get_changelog_version() {
    local changelog="$1/debian/changelog"
    [ ! -f "$changelog" ] && return
    head -1 "$changelog" | sed -n 's/^[^ ]* (\([^)]*\)).*/\1/p'
}

extract_git_commit() {
    echo "$1" | sed -n 's/.*+git[0-9]*\.\([a-f0-9]*\)ppa.*/\1/p'
}

extract_release_version() {
    echo "$1" | sed 's/ppa[0-9]*$//' | sed 's/-[0-9]*$//'
}

update_changelog() {
    local package_dir="$1"
    local new_version="$2"
    local message="$3"
    local changelog="$package_dir/debian/changelog"
    
    local source_name
    source_name=$(head -1 "$changelog" | cut -d' ' -f1)
    
    local temp_changelog
    temp_changelog=$(mktemp)
    {
        echo "$source_name ($new_version) unstable; urgency=medium"
        echo ""
        echo "  * $message"
        echo ""
        echo " -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
        echo ""
        cat "$changelog"
    } > "$temp_changelog"
    
    mv "$temp_changelog" "$changelog"
    success "   Updated changelog to $new_version"
}

if [ "$UPDATE_MODE" = true ]; then
    info "🔄 Checking and updating packages in: $BASE_DIR"
else
    info "🔍 Checking for package updates in: $BASE_DIR"
fi
echo "" >&2

UPDATED_PACKAGES=()

for pkg_info in "${PACKAGES[@]}"; do
    IFS=':' read -r package repo type <<< "$pkg_info"
    package_dir="$BASE_DIR/$package"
    
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
        
        git_info=$(get_git_info "$repo")
        if [ -z "$git_info" ]; then
            warn "   Could not fetch git info from $repo"
            echo "" >&2
            continue
        fi
        
        IFS=':' read -r latest_commit commit_count base_version <<< "$git_info"
        info "   Latest: commit $latest_commit (#$commit_count), base: $base_version"
        
        if [ "${current_commit:0:8}" != "${latest_commit:0:8}" ]; then
            new_version="${base_version}+git${commit_count}.${latest_commit}ppa1"
            success "   ✨ Update available: ${current_commit:-none} → $latest_commit"
            
            if [ "$UPDATE_MODE" = true ]; then
                update_changelog "$package_dir" "$new_version" "Git snapshot (commit $commit_count: $latest_commit)"
            fi
            
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
            new_version="${latest_tag}ppa1"
            success "   ✨ Update available: $current_base → $latest_tag"
            
            if [ "$UPDATE_MODE" = true ]; then
                update_changelog "$package_dir" "$new_version" "Update to upstream version $latest_tag"
            fi
            
            UPDATED_PACKAGES+=("$package")
        else
            info "   ✓ Already up to date"
        fi
    fi
    
    echo "" >&2
done

info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ${#UPDATED_PACKAGES[@]} -gt 0 ]; then
    if [ "$UPDATE_MODE" = true ]; then
        success "Updated ${#UPDATED_PACKAGES[@]} package(s):"
    else
        success "Found ${#UPDATED_PACKAGES[@]} package(s) with updates:"
    fi
    for pkg in "${UPDATED_PACKAGES[@]}"; do
        info "   • $pkg"
    done
    echo "" >&2
    echo "${UPDATED_PACKAGES[*]}"
else
    info "✓ All packages are up to date"
    echo ""
fi

