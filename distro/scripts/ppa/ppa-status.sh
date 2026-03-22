#!/bin/bash
# Unified PPA status checker for danklinux packages
# Checks build status for all packages in the PPA via Launchpad API
# Usage: ./distro/scripts/ppa-status.sh [package-name]
#
# Examples:
#   ./distro/scripts/ppa-status.sh              # Check all packages
#   ./distro/scripts/ppa-status.sh cliphist     # Check specific package

PPA_OWNER="avengemedia"
PPA_NAME="danklinux"
LAUNCHPAD_API="https://api.launchpad.net/1.0"
DISTRO_SERIES_LIST=(questing resolute)

# Define packages (sync with ppa-upload.sh)
ALL_PACKAGES=(cpptrace cliphist ghostty matugen niri niri-git quickshell quickshell-git xwayland-satellite xwayland-satellite-git)

# Check for required tools
if ! command -v curl &> /dev/null; then
    echo "Error: curl is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Get packages to check
if [[ -n "$1" ]]; then
    PACKAGES=("$1")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

# Function to get build status color and symbol
get_status_display() {
    local status="$1"
    case "$status" in
        "Successfully built")
            echo -e "✅ \033[0;32m$status\033[0m"
            ;;
        "Failed to build")
            echo -e "❌ \033[0;31m$status\033[0m"
            ;;
        "Needs building"|"Currently building")
            echo -e "⏳ \033[0;33m$status\033[0m"
            ;;
        "Dependency wait")
            echo -e "⚠️ \033[0;33m$status\033[0m"
            ;;
        "Chroot problem")
            echo -e "🔧 \033[0;31m$status\033[0m"
            ;;
        "Uploading build")
            echo -e "📤 \033[0;36m$status\033[0m"
            ;;
        *)
            echo -e "❓ \033[0;37m$status\033[0m"
            ;;
    esac
}

# Get the archive link for the PPA
PPA_ARCHIVE="${LAUNCHPAD_API}/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}"

echo "Checking PPA: ${PPA_OWNER}/${PPA_NAME}"
echo "Distributions: Ubuntu ${DISTRO_SERIES_LIST[*]}"
echo ""

for DISTRO_SERIES in "${DISTRO_SERIES_LIST[@]}"; do
for pkg in "${PACKAGES[@]}"; do
    echo "=========================================="
    echo "=== $pkg (Ubuntu ${DISTRO_SERIES}) ==="
    echo "=========================================="
    
    # Get published sources for this package
    SOURCES_URL="${PPA_ARCHIVE}?ws.op=getPublishedSources&source_name=${pkg}&distro_series=${LAUNCHPAD_API}/ubuntu/${DISTRO_SERIES}&status=Published"
    
    SOURCES=$(curl -s "$SOURCES_URL" 2>/dev/null)
    
    if [[ -z "$SOURCES" ]] || [[ "$SOURCES" == "null" ]]; then
        echo "  ⚠️  No published sources found"
        echo ""
        continue
    fi
    
    # Get the latest source
    TOTAL=$(echo "$SOURCES" | jq '.total_size // 0')
    
    if [[ "$TOTAL" == "0" ]]; then
        echo "  ⚠️  No published sources found for $DISTRO_SERIES"
        echo ""
        continue
    fi
    
    # Get most recent entry
    ENTRY=$(echo "$SOURCES" | jq '.entries[0]')
    
    if [[ "$ENTRY" == "null" ]]; then
        echo "  ⚠️  No source entries found"
        echo ""
        continue
    fi
    
    # Extract source info
    VERSION=$(echo "$ENTRY" | jq -r '.source_package_version // "unknown"')
    STATUS=$(echo "$ENTRY" | jq -r '.status // "unknown"')
    DATE_PUBLISHED=$(echo "$ENTRY" | jq -r '.date_published // "unknown"')
    SELF_LINK=$(echo "$ENTRY" | jq -r '.self_link // ""')
    
    echo "  📦 Version: $VERSION"
    echo "  📅 Published: ${DATE_PUBLISHED%T*}"
    echo "  📋 Source Status: $STATUS"
    echo ""
    
    # Get builds for this source
    if [[ -n "$SELF_LINK" && "$SELF_LINK" != "null" ]]; then
        BUILDS_URL="${SELF_LINK}?ws.op=getBuilds"
        BUILDS=$(curl -s "$BUILDS_URL" 2>/dev/null)
        
        if [[ -n "$BUILDS" && "$BUILDS" != "null" ]]; then
            BUILD_COUNT=$(echo "$BUILDS" | jq '.total_size // 0')
            
            if [[ "$BUILD_COUNT" -gt 0 ]]; then
                echo "  Builds:"
                echo "$BUILDS" | jq -r '.entries[] | "\(.arch_tag) \(.buildstate)"' 2>/dev/null | while read -r line; do
                    ARCH=$(echo "$line" | awk '{print $1}')
                    BUILD_STATUS=$(echo "$line" | cut -d' ' -f2-)
                    DISPLAY=$(get_status_display "$BUILD_STATUS")
                    echo "    $ARCH: $DISPLAY"
                done
            fi
        fi
    fi
    
    # Alternative: Get build records directly from archive
    BUILD_RECORDS_URL="${PPA_ARCHIVE}?ws.op=getBuildRecords&source_name=${pkg}"
    BUILD_RECORDS=$(curl -s "$BUILD_RECORDS_URL" 2>/dev/null)
    
    if [[ -n "$BUILD_RECORDS" && "$BUILD_RECORDS" != "null" ]]; then
        RECORD_COUNT=$(echo "$BUILD_RECORDS" | jq '.total_size // 0')
        
        if [[ "$RECORD_COUNT" -gt 0 ]]; then
            echo ""
            echo "  Recent build history:"
            
            # Get unique version+arch combinations
            echo "$BUILD_RECORDS" | jq -r '.entries[:6][] | "\(.source_package_version) \(.arch_tag) \(.buildstate)"' 2>/dev/null | while read -r line; do
                VER=$(echo "$line" | awk '{print $1}')
                ARCH=$(echo "$line" | awk '{print $2}')
                BUILD_STATUS=$(echo "$line" | cut -d' ' -f3-)
                DISPLAY=$(get_status_display "$BUILD_STATUS")
                echo "    $VER ($ARCH): $DISPLAY"
            done
        fi
    fi
    
    echo ""
done
done

echo "=========================================="
echo "Status check complete!"
echo ""
echo "View full PPA at: https://launchpad.net/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}"
