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
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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
    "niri-git:niri-wm/niri:git"
    "quickshell-git:quickshell-mirror/quickshell:git"
    "xwayland-satellite-git:Supreeeme/xwayland-satellite:git"
    "quickshell:quickshell-mirror/quickshell:release"
    "niri:niri-wm/niri:release"
    "xwayland-satellite:Supreeeme/xwayland-satellite:release"
    "cliphist:sentriz/cliphist:release"
    "matugen:InioX/matugen:release"
    "ghostty:ghostty-org/ghostty:release"
    "danksearch:AvengeMedia/danksearch:release"
    "dgop:AvengeMedia/dgop:release"
)

get_latest_tag() {
    local repo="$1"
    local tag
    # Use centralized fetch script with retry/token support
    tag=$("$SCRIPT_DIR/../common/fetch-version.sh" "$repo" "release")
    
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
    # Extract commit from ~git, +git, +pin (legacy), +snapshot, and ~ variants
    echo "$1" | sed -n 's/.*[~+]\(git\|pin\|snapshot\)[0-9]*\.\([a-f0-9]*\).*/\2/p'
}

extract_release_version() {
    echo "$1" | sed 's/ppa[0-9]*$//' | sed 's/-[0-9]*$//'
}

# +pin/~pin are legacy; +snapshot/~snapshot is current
is_debian_version_snapshot_ish() {
    local v="$1"
    [[ "$v" == *"+pin"* ]] || [[ "$v" == *"~pin"* ]] || \
    [[ "$v" == *"+snapshot"* ]] || [[ "$v" == *"~snapshot"* ]]
}

update_service_file() {
    local package_dir="$1"
    local new_version="$2"
    local service_file="$package_dir/_service"
    
    [ ! -f "$service_file" ] && return
    
    sed -i "s|/releases/download/v[0-9.]\+/|/releases/download/v$new_version/|g" "$service_file"
    sed -i "s|/releases/download/[0-9.]\+/|/releases/download/$new_version/|g" "$service_file"
    
    sed -i "s|/archive/refs/tags/v[0-9.]\+\.tar|/archive/refs/tags/v$new_version.tar|g" "$service_file"
    sed -i "s|/archive/refs/tags/[0-9.]\+\.tar|/archive/refs/tags/$new_version.tar|g" "$service_file"
    
    sed -i "s|niri-[0-9.]\+-|niri-$new_version-|g" "$service_file"
    sed -i "s|matugen-[0-9.]\+-|matugen-$new_version-|g" "$service_file"
    
    success "   Updated _service file to $new_version"
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
    
    # Also update _service file if it exists
    update_service_file "$package_dir" "${new_version%ppa*}"
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
        # Snapshot (only for quickshell stable) — see distro/snapshots.yaml
        USE_SNAPSHOT=false
        if [ "$package" = "quickshell" ] && [ -f "$REPO_ROOT/distro/snapshots.yaml" ]; then
            if command -v yq &> /dev/null; then
                SNAPSHOT_ENABLED=$(yq eval '.quickshell.enabled' "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "false")
                if [ "$SNAPSHOT_ENABLED" = "true" ]; then
                    SNAPSHOT_BASE_VER=$(yq eval '.quickshell.base_version' "$REPO_ROOT/distro/snapshots.yaml")

                    # Fetch latest release; if it is newer than base_version, use release tarball instead
                    latest_tag=$(get_latest_tag "$repo")

                    if [[ -n "$latest_tag" ]] && [[ "$(printf '%s\n' "$latest_tag" "$SNAPSHOT_BASE_VER" | sort -V | tail -1)" != "$SNAPSHOT_BASE_VER" ]]; then
                        info "   📌 Snapshot override: new stable release $latest_tag (newer than base $SNAPSHOT_BASE_VER)"
                        USE_SNAPSHOT=false
                    else
                        info "   📌 Using snapshot commit (no stable release newer than $SNAPSHOT_BASE_VER)"
                        USE_SNAPSHOT=true
                        SNAP_COMMIT=$(yq eval '.quickshell.commit' "$REPO_ROOT/distro/snapshots.yaml")
                        SNAP_COUNT=$(yq eval '.quickshell.commit_count' "$REPO_ROOT/distro/snapshots.yaml")
                        SNAP_BASE=$(yq eval '.quickshell.base_version' "$REPO_ROOT/distro/snapshots.yaml")
                    fi
                fi
            fi
        fi

        if [ "$USE_SNAPSHOT" = "true" ]; then
            current_commit=$(extract_git_commit "$current_version")
            info "   Current: $current_version (snapshot commit: ${current_commit:-unknown})"
            info "   Target:  snapshot at ${SNAP_COMMIT:0:8}"

            if [ "${current_commit:0:8}" != "${SNAP_COMMIT:0:8}" ]; then
                new_version="${SNAP_BASE}.1+snapshot${SNAP_COUNT}.${SNAP_COMMIT:0:8}ppa1"
                success "   ✨ Update to snapshot commit: ${current_commit:-none} → ${SNAP_COMMIT:0:8}"

                if [ "$UPDATE_MODE" = true ]; then
                    update_changelog "$package_dir" "$new_version" "Snapshot at commit $SNAP_COUNT (${SNAP_COMMIT:0:8}) — pre-release stable with latest features"
                    service_file="$package_dir/_service"
                    if [ -f "$service_file" ]; then
                        sed -i "s|/archive/refs/tags/v[0-9.]\+\.tar|/archive/$SNAP_COMMIT.tar|g" "$service_file"
                        sed -i "s|/archive/[a-f0-9]\{40\}\.tar|/archive/$SNAP_COMMIT.tar|g" "$service_file"
                    fi
                fi

                UPDATED_PACKAGES+=("$package")
            else
                info "   ✓ Already at snapshot commit"
            fi
        else
            # Normal release handling
            current_base=$(extract_release_version "$current_version")
            info "   Current: $current_version (base: $current_base)"

            latest_tag=$(get_latest_tag "$repo")
            if [ -z "$latest_tag" ]; then
                warn "   Could not fetch latest tag from $repo"
                echo "" >&2
                continue
            fi

            info "   Latest release: $latest_tag"

            if is_debian_version_snapshot_ish "$current_version"; then
                snap_ref_base=$(echo "$current_version" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

                if dpkg --compare-versions "$latest_tag" "gt" "$snap_ref_base"; then
                    info "   🎉 New stable release $latest_tag available (snapshot base: $snap_ref_base)"
                else
                    info "   📌 On snapshot (base: $snap_ref_base, latest release: $latest_tag)"
                    info "      Will move to a tagged release when one is newer than $snap_ref_base"
                    echo "" >&2
                    continue
                fi
            fi

            if [ "$current_base" != "$latest_tag" ]; then
                new_version="${latest_tag}ppa1"
                success "   ✨ Update available: $current_base → $latest_tag"

                if [ "$UPDATE_MODE" = true ]; then
                    if is_debian_version_snapshot_ish "$current_version"; then
                        info "   🔄 Transitioning from snapshot to stable release"
                        service_file="$package_dir/_service"
                        if [ -f "$service_file" ]; then
                            sed -i "s|/archive/[a-f0-9]\{40\}\.tar|/archive/refs/tags/v$latest_tag.tar|g" "$service_file"
                        fi
                    fi

                    update_changelog "$package_dir" "$new_version" "Update to upstream version $latest_tag"
                fi

                UPDATED_PACKAGES+=("$package")
            else
                info "   ✓ Already up to date"
            fi
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

