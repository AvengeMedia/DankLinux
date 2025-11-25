#!/bin/bash
# Build and upload PPA package with automatic cleanup
# Usage: ./build-and-upload.sh <package-dir> <ppa-name> [ubuntu-series] [--keep-builds]
#
# Example:
#   ./build-and-upload.sh ../dgop danklinux noble
#   ./build-and-upload.sh ../quickshell-git danklinux noble --keep-builds

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

KEEP_BUILDS=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--keep-builds" ]; then
        KEEP_BUILDS=true
    else
        ARGS+=("$arg")
    fi
done

if [ ${#ARGS[@]} -lt 2 ]; then
    error "Usage: $0 <package-dir> <ppa-name> [ubuntu-series] [--keep-builds]"
    echo
    echo "Arguments:"
    echo "  package-dir     : Path to package directory (e.g., ../dgop)"
    echo "  ppa-name        : PPA name (e.g., danklinux, dms, dms-git)"
    echo "  ubuntu-series   : Ubuntu series (optional, default: questing)"
    echo "                    Supported: questing (25.10) and newer only"
    echo "                    Note: Requires Qt 6.6+ (quickshell requirement)"
    echo "  --keep-builds   : Keep build artifacts after upload (optional)"
    echo
    echo "Examples:"
    echo "  $0 ../dgop danklinux questing"
    echo "  $0 ../quickshell-git danklinux questing --keep-builds"
    echo "  $0 ../quickshell-git danklinux  # Defaults to questing"
    exit 1
fi

PACKAGE_DIR="${ARGS[0]}"
PPA_NAME="${ARGS[1]}"
UBUNTU_SERIES="${ARGS[2]:-questing}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/ppa-build.sh"
UPLOAD_SCRIPT="$SCRIPT_DIR/ppa-dput.sh"

# Validate scripts exist
if [ ! -f "$BUILD_SCRIPT" ]; then
    error "Build script not found: $BUILD_SCRIPT"
    exit 1
fi

# Get absolute path
PACKAGE_DIR=$(cd "$PACKAGE_DIR" && pwd)
PACKAGE_NAME=$(basename "$PACKAGE_DIR")
PARENT_DIR=$(dirname "$PACKAGE_DIR")

info "Building and uploading: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "PPA: ppa:avengemedia/$PPA_NAME"
info "Ubuntu series: $UBUNTU_SERIES"
echo

# Step 1: Build source package
info "Step 1: Building source package..."
if ! "$BUILD_SCRIPT" "$PACKAGE_DIR" "$UBUNTU_SERIES"; then
    error "Build failed!"
    exit 1
fi

# Find the changes file
CHANGES_FILE=$(find "$PARENT_DIR" -maxdepth 1 -name "${PACKAGE_NAME}_*_source.changes" -type f | sort -V | tail -1)

if [ -z "$CHANGES_FILE" ]; then
    error "Changes file not found in $PARENT_DIR"
    exit 1
fi

info "Found changes file: $CHANGES_FILE"
echo

# Step 2: Upload to PPA
info "Step 2: Uploading to PPA..."

# Check if using lftp (for all PPAs) or dput
if [ "$PPA_NAME" = "danklinux" ] || [ "$PPA_NAME" = "dms" ] || [ "$PPA_NAME" = "dms-git" ]; then
    # Use lftp for upload (dput not available on Fedora)
    warn "Using lftp for upload"
    
    # Extract version from changes file
    VERSION=$(grep "^Version:" "$CHANGES_FILE" | awk '{print $2}')
    SOURCE_NAME=$(grep "^Source:" "$CHANGES_FILE" | awk '{print $2}')
    
    BUILD_DIR=$(dirname "$CHANGES_FILE")
    CHANGES_BASENAME=$(basename "$CHANGES_FILE")
    DSC_FILE="${CHANGES_BASENAME/_source.changes/.dsc}"
    TARBALL="${CHANGES_BASENAME/_source.changes/.tar.xz}"
    BUILDINFO="${CHANGES_BASENAME/_source.changes/_source.buildinfo}"
    
    # Check all files exist
    MISSING_FILES=()
    [ ! -f "$BUILD_DIR/$DSC_FILE" ] && MISSING_FILES+=("$DSC_FILE")
    [ ! -f "$BUILD_DIR/$TARBALL" ] && MISSING_FILES+=("$TARBALL")
    [ ! -f "$BUILD_DIR/$BUILDINFO" ] && MISSING_FILES+=("$BUILDINFO")
    
    if [ ${#MISSING_FILES[@]} -gt 0 ]; then
        error "Missing required files:"
        for file in "${MISSING_FILES[@]}"; do
            error "  - $file"
        done
        exit 1
    fi
    
    info "Uploading files:"
    info "  - $CHANGES_BASENAME"
    info "  - $DSC_FILE"
    info "  - $TARBALL"
    info "  - $BUILDINFO"
    echo
    
    # Create temporary lftp script
    # lftp needs to change to the build directory first, then upload files
    LFTP_SCRIPT=$(mktemp)
    cat > "$LFTP_SCRIPT" <<EOF
cd ~avengemedia/ubuntu/$PPA_NAME/
lcd $BUILD_DIR
mput $CHANGES_BASENAME
mput $DSC_FILE
mput $TARBALL
mput $BUILDINFO
bye
EOF
    
    if lftp -d ftp://anonymous:@ppa.launchpad.net < "$LFTP_SCRIPT"; then
        success "Upload successful!"
        rm -f "$LFTP_SCRIPT"
    else
        error "Upload failed!"
        rm -f "$LFTP_SCRIPT"
        exit 1
    fi
else
    # Use dput for other PPAs
    if [ ! -f "$UPLOAD_SCRIPT" ]; then
        error "Upload script not found: $UPLOAD_SCRIPT"
        exit 1
    fi

    # Auto-confirm upload (pipe 'y' to the confirmation prompt)
    if ! echo "y" | "$UPLOAD_SCRIPT" "$CHANGES_FILE" "$PPA_NAME"; then
        error "Upload failed!"
        exit 1
    fi
fi

echo
success "Package uploaded successfully!"
info "Monitor build progress at:"
echo "  https://launchpad.net/~avengemedia/+archive/ubuntu/$PPA_NAME/+packages"
echo

# Step 3: Cleanup (unless --keep-builds is specified)
if [ "$KEEP_BUILDS" = "false" ]; then
    info "Step 3: Cleaning up build artifacts..."

    # Find all build artifacts in parent directory
    ARTIFACTS=(
        "${PACKAGE_NAME}_*.dsc"
        "${PACKAGE_NAME}_*.tar.xz"
        "${PACKAGE_NAME}_*.tar.gz"
        "${PACKAGE_NAME}_*_source.changes"
        "${PACKAGE_NAME}_*_source.buildinfo"
        "${PACKAGE_NAME}_*_source.build"
    )

    REMOVED=0
    for pattern in "${ARTIFACTS[@]}"; do
        for file in "$PARENT_DIR"/$pattern; do
            if [ -f "$file" ]; then
                rm -f "$file"
                REMOVED=$((REMOVED + 1))
            fi
        done
    done

    # Clean up downloaded binaries in package directory (for packages like danksearch)
    case "$PACKAGE_NAME" in
        danksearch)
            if [ -f "$PACKAGE_DIR/dsearch-amd64" ]; then
                rm -f "$PACKAGE_DIR/dsearch-amd64"
                REMOVED=$((REMOVED + 1))
            fi
            if [ -f "$PACKAGE_DIR/dsearch-arm64" ]; then
                rm -f "$PACKAGE_DIR/dsearch-arm64"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
        hyprpicker)
            # Remove downloaded tarballs
            for tarball in pugixml.tar.gz hyprutils.tar.gz hyprwayland-scanner.tar.gz hyprpicker.tar.gz; do
                if [ -f "$PACKAGE_DIR/$tarball" ]; then
                    rm -f "$PACKAGE_DIR/$tarball"
                    REMOVED=$((REMOVED + 1))
                fi
            done
            ;;
        dms)
            # Remove downloaded binaries and source
            if [ -f "$PACKAGE_DIR/dms-distropkg-amd64.gz" ]; then
                rm -f "$PACKAGE_DIR/dms-distropkg-amd64.gz"
                REMOVED=$((REMOVED + 1))
            fi
            if [ -f "$PACKAGE_DIR/dms-source.tar.gz" ]; then
                rm -f "$PACKAGE_DIR/dms-source.tar.gz"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
        dms-git)
            # Remove downloaded binary
            if [ -f "$PACKAGE_DIR/dms-distropkg-amd64.gz" ]; then
                rm -f "$PACKAGE_DIR/dms-distropkg-amd64.gz"
                REMOVED=$((REMOVED + 1))
            fi
            # Remove git source directory
            if [ -d "$PACKAGE_DIR/dms-git-repo" ]; then
                rm -rf "$PACKAGE_DIR/dms-git-repo"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
        quickshell-git)
            # Remove git source directory
            if [ -d "$PACKAGE_DIR/quickshell-source" ]; then
                rm -rf "$PACKAGE_DIR/quickshell-source"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
        niri-git)
            # Remove git source directory
            if [ -d "$PACKAGE_DIR/niri-source" ]; then
                rm -rf "$PACKAGE_DIR/niri-source"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
        niri)
            # Remove downloaded source directory and tarball
            VERSION=$(dpkg-parsechangelog -S Version -l "$PACKAGE_DIR/debian/changelog" | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//' 2>/dev/null)
            if [ -n "$VERSION" ] && [ -d "$PACKAGE_DIR/niri-${VERSION}" ]; then
                rm -rf "$PACKAGE_DIR/niri-${VERSION}"
                REMOVED=$((REMOVED + 1))
            fi
            if [ -f "$PACKAGE_DIR/niri-download.tar.gz" ]; then
                rm -f "$PACKAGE_DIR/niri-download.tar.gz"
                REMOVED=$((REMOVED + 1))
            fi
            ;;
    esac

    if [ $REMOVED -gt 0 ]; then
        success "Removed $REMOVED build artifact(s)"
    else
        info "No build artifacts to clean up"
    fi
else
    info "Keeping build artifacts (--keep-builds specified)"
    info "Build artifacts in: $PARENT_DIR"
fi

echo
success "Done!"

