#!/bin/bash
# Unified OBS status checker for danklinux packages
# Checks all platforms (Debian, OpenSUSE) and architectures (x86_64, aarch64)
# Only pulls logs if build failed
# Usage: ./distro/scripts/obs-status.sh [package-name]
#
# Examples:
#   ./distro/scripts/obs-status.sh              # Check all packages
#   ./distro/scripts/obs-status.sh cliphist     # Check specific package

OBS_BASE_PROJECT="home:AvengeMedia:danklinux"
OBS_BASE="$HOME/.cache/osc-checkouts"

# Define packages (sync with obs-upload.sh)
ALL_PACKAGES=(cliphist matugen niri niri-git quickshell quickshell-git xwayland-satellite xwayland-satellite-git danksearch dgop ghostty)

# Define repositories and architectures to check
REPOS=("Debian_13" "openSUSE_Tumbleweed" "16.0")
ARCHES=("x86_64" "aarch64")

# Get packages to check
if [[ -n "$1" ]]; then
    PACKAGES=("$1")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

cd "$OBS_BASE"

for pkg in "${PACKAGES[@]}"; do
    echo "=========================================="
    echo "=== $pkg ==="
    echo "=========================================="
    
    # Checkout if needed
    if [[ ! -d "$OBS_BASE_PROJECT/$pkg" ]]; then
        osc co "$OBS_BASE_PROJECT/$pkg" 2>&1 | tail -1
    fi
    
    cd "$OBS_BASE_PROJECT/$pkg"
    
    # Get all build results
    ALL_RESULTS=$(osc results 2>&1)
    
    # Check each repository and architecture
    FAILED_BUILDS=()
    for repo in "${REPOS[@]}"; do
        for arch in "${ARCHES[@]}"; do
            STATUS=$(echo "$ALL_RESULTS" | grep "$repo.*$arch" | awk '{print $NF}' | head -1)
            
            if [[ -n "$STATUS" ]]; then
                # Color code status
                case "$STATUS" in
                    succeeded)
                        COLOR="\033[0;32m"  # Green
                        SYMBOL="✅"
                        ;;
                    failed)
                        COLOR="\033[0;31m"  # Red
                        SYMBOL="❌"
                        FAILED_BUILDS+=("$repo $arch")
                        ;;
                    unresolvable)
                        COLOR="\033[0;33m"  # Yellow
                        SYMBOL="⚠️"
                        ;;
                    *)
                        COLOR="\033[0;37m"  # White
                        SYMBOL="⏳"
                        ;;
                esac
                echo -e "  $SYMBOL $repo $arch: ${COLOR}$STATUS\033[0m"
            fi
        done
    done
    
    # Pull logs for failed builds
    if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
        echo ""
        echo "  📋 Fetching logs for failed builds..."
        for build in "${FAILED_BUILDS[@]}"; do
            read -r repo arch <<< "$build"
            echo ""
            echo "  ────────────────────────────────────────────"
            echo "  Build log: $repo $arch"
            echo "  ────────────────────────────────────────────"
            osc remotebuildlog "$OBS_BASE_PROJECT" "$pkg" "$repo" "$arch" 2>&1 | tail -100
        done
    fi
    
    echo ""
    cd - > /dev/null
done

echo "=========================================="
echo "Status check complete!"

