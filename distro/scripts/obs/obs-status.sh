#!/bin/bash
# Unified OBS status checker for danklinux packages
# Checks all platforms (Debian, OpenSUSE) and architectures (x86_64, aarch64)
# Uses OSC API for log fetching
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
REPOS=("Debian_13" "openSUSE_Tumbleweed" "openSUSE_Slowroll" "16.0")
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
                        FAILED_BUILDS+=("$repo $arch")
                        ;;
                    building|scheduled|finished)
                        COLOR="\033[0;37m"  # White
                        SYMBOL="⏳"
                        # Don't fetch logs for in-progress or finished builds
                        ;;
                    *)
                        COLOR="\033[0;33m"
                        SYMBOL="⚠️"
                        FAILED_BUILDS+=("$repo $arch")
                        ;;
                esac
                echo -e "  $SYMBOL $repo $arch: ${COLOR}$STATUS\033[0m"
            fi
        done
    done
    
    # Pull logs for failed/unresolvable builds using OSC API
    if [[ ${#FAILED_BUILDS[@]} -gt 0 ]]; then
        echo ""
        echo "  📋 Fetching logs for failed/unresolvable builds..."
        for build in "${FAILED_BUILDS[@]}"; do
            read -r repo arch <<< "$build"
            echo ""
            echo "  ────────────────────────────────────────────"
            echo "  Build log: $repo $arch"
            echo "  ────────────────────────────────────────────"
            
            # Try multiple API endpoints for different types of failures
            BUILD_STATUS=$(osc api "/build/$OBS_BASE_PROJECT/$repo/$arch/$pkg" 2>&1)
            if [[ $? -eq 0 && -n "$BUILD_STATUS" ]]; then
                # Extract useful info from XML if available
                if echo "$BUILD_STATUS" | grep -q "unresolvable\|failed"; then
                    echo "  Build status details:"
                    echo "$BUILD_STATUS" | grep -E "(code|state|details)" | head -5 | sed 's/^/    /'
                    echo ""
                fi
            fi
            
            # Fetch the main build log
            LOG_OUTPUT=$(osc api "/build/$OBS_BASE_PROJECT/$repo/$arch/$pkg/_log" 2>&1)
            API_EXIT=$?
            if [[ $API_EXIT -eq 0 && -n "$LOG_OUTPUT" && "$LOG_OUTPUT" != *"<error"* && "$LOG_OUTPUT" != *"not found"* && "$LOG_OUTPUT" != *"404"* ]]; then
                echo "$LOG_OUTPUT" | tail -100
            else
                if echo "$ALL_RESULTS" | grep -q "$repo.*$arch.*unresolvable"; then
                    echo "  Attempting to fetch unresolvable reason..."
                    REASON=$(osc api "/build/$OBS_BASE_PROJECT/$repo/$arch/$pkg/_reason" 2>&1)
                    if [[ $? -eq 0 && -n "$REASON" && "$REASON" != *"<error"* ]]; then
                        if echo "$REASON" | grep -q "<reason>"; then
                            EXPLAIN=$(echo "$REASON" | grep -oP '<explain>\K[^<]*' || echo "metadata changes")
                            echo "  Reason: $EXPLAIN"
                            
                            # Count package changes
                            PKG_CHANGE_COUNT=$(echo "$REASON" | grep -c '<packagechange' || echo "0")
                            if [[ $PKG_CHANGE_COUNT -gt 0 ]]; then
                                echo ""
                                echo "  Package changes ($PKG_CHANGE_COUNT):"
                                echo "$REASON" | grep -oP '<packagechange[^>]*/>' | \
                                    sed 's/<packagechange change="\([^"]*\)" key="\([^"]*\)"\/>/    - \1: \2/' | \
                                    head -10
                                if [[ $PKG_CHANGE_COUNT -gt 10 ]]; then
                                    echo "    ... (and $((PKG_CHANGE_COUNT - 10)) more)"
                                fi
                            fi
                            
                            if [[ "$EXPLAIN" == "meta change" ]]; then
                                echo ""
                                echo "  ℹ️  Note: This is typically a repository metadata change issue."
                                echo "     The build may have actually succeeded (check logs below)."
                                echo "     Updating obs-project.conf may help, but builds often work despite this status."
                            fi
                        else
                            echo "$REASON"
                        fi
                    fi
                fi
                
                # Fallback to remotebuildlog if API fails
                echo "  (Trying remotebuildlog as fallback...)"
                osc remotebuildlog "$OBS_BASE_PROJECT" "$pkg" "$repo" "$arch" 2>&1 | tail -100
            fi
        done
    fi
    
    echo ""
    cd - > /dev/null
done

echo "=========================================="
echo "Status check complete!"

