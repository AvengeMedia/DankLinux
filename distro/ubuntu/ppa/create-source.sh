#!/bin/bash
# Generic source package builder for danklinux PPA packages
# Usage: ./create-source.sh <package-dir> [ubuntu-series]
#
# Example:
#   ./create-source.sh ../matugen questing
#   ./create-source.sh ../quickshell-git questing

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
    error "Usage: $0 <package-dir> [ubuntu-series]"
    echo
    echo "Arguments:"
    echo "  package-dir     : Path to package directory (e.g., ../matugen)"
    echo "  ubuntu-series   : Ubuntu series (optional, default: questing)"
    echo "                    Supported: questing (25.10) and newer only"
    echo "                    Note: Requires Qt 6.6+ (quickshell requirement)"
    echo
    echo "Examples:"
    echo "  $0 ../matugen questing"
    echo "  $0 ../quickshell-git questing"
    exit 1
fi

PACKAGE_DIR="$1"
UBUNTU_SERIES="${2:-questing}"

# Validate package directory
if [ ! -d "$PACKAGE_DIR" ]; then
    error "Package directory not found: $PACKAGE_DIR"
    exit 1
fi

if [ ! -d "$PACKAGE_DIR/debian" ]; then
    error "No debian/ directory found in $PACKAGE_DIR"
    exit 1
fi

# Get absolute path
PACKAGE_DIR=$(cd "$PACKAGE_DIR" && pwd)
PACKAGE_NAME=$(basename "$PACKAGE_DIR")

info "Building source package for: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "Target Ubuntu series: $UBUNTU_SERIES"

# Check for required files
REQUIRED_FILES=(
    "debian/control"
    "debian/rules"
    "debian/changelog"
    "debian/copyright"
    "debian/source/format"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$PACKAGE_DIR/$file" ]; then
        error "Required file missing: $file"
        exit 1
    fi
done

# Verify GPG key is set up
info "Checking GPG key setup..."
if ! gpg --list-secret-keys &> /dev/null; then
    error "No GPG secret keys found. Please set up GPG first!"
    error "See GPG_SETUP.md for instructions"
    exit 1
fi

success "GPG key found"

# Check if debuild is installed
if ! command -v debuild &> /dev/null; then
    error "debuild not found. Install devscripts:"
    error "  sudo dnf install devscripts"
    exit 1
fi

# Extract package info from changelog
cd "$PACKAGE_DIR"
CHANGELOG_VERSION=$(dpkg-parsechangelog -S Version)
SOURCE_NAME=$(dpkg-parsechangelog -S Source)

info "Source package: $SOURCE_NAME"
info "Version: $CHANGELOG_VERSION"

# Check if version targets correct Ubuntu series
CHANGELOG_SERIES=$(dpkg-parsechangelog -S Distribution)
if [ "$CHANGELOG_SERIES" != "$UBUNTU_SERIES" ] && [ "$CHANGELOG_SERIES" != "UNRELEASED" ]; then
    warn "Changelog targets '$CHANGELOG_SERIES' but building for '$UBUNTU_SERIES'"
    warn "Consider updating changelog with: dch -r '' -D $UBUNTU_SERIES"
fi

# Detect package type and update version automatically
cd "$PACKAGE_DIR"

# Function to get latest tag from GitHub
get_latest_tag() {
    local repo="$1"
    # Try GitHub API first (faster)
    if command -v curl &> /dev/null; then
        LATEST_TAG=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep '"tag_name":' | sed 's/.*"tag_name": "\(.*\)".*/\1/' | head -1)
        if [ -n "$LATEST_TAG" ]; then
            echo "$LATEST_TAG" | sed 's/^v//'
            return
        fi
    fi
    # Fallback: clone and get latest tag
    TEMP_REPO=$(mktemp -d)
    if git clone --depth=1 --quiet "https://github.com/$repo.git" "$TEMP_REPO" 2>/dev/null; then
        LATEST_TAG=$(cd "$TEMP_REPO" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
        rm -rf "$TEMP_REPO"
        echo "$LATEST_TAG"
    fi
}

# Detect if package is git-based
IS_GIT_PACKAGE=false
GIT_REPO=""
SOURCE_DIR=""

# Check package name for -git suffix
if [[ "$PACKAGE_NAME" == *"-git" ]]; then
    IS_GIT_PACKAGE=true
fi

# Check rules file for git clone patterns and extract repo
if grep -q "git clone" debian/rules 2>/dev/null; then
    IS_GIT_PACKAGE=true
    # Extract GitHub repo URL from rules
    GIT_URL=$(grep -o "git clone.*https://github.com/[^/]*/[^/]*\.git" debian/rules 2>/dev/null | head -1 | sed 's/.*github\.com\///' | sed 's/\.git.*//' || echo "")
    if [ -n "$GIT_URL" ]; then
        GIT_REPO="$GIT_URL"
    fi
fi

# Special handling for known packages
case "$PACKAGE_NAME" in
    quickshell-git)
        IS_GIT_PACKAGE=true
        GIT_REPO="quickshell-mirror/quickshell"
        SOURCE_DIR="quickshell-source"
        ;;
    niri-git)
        IS_GIT_PACKAGE=true
        GIT_REPO="YaLTeR/niri"
        SOURCE_DIR="niri"
        ;;
    dms-git)
        IS_GIT_PACKAGE=true
        GIT_REPO="AvengeMedia/DankMaterialShell"
        SOURCE_DIR="dms-git-repo"
        ;;
    dms)
        GIT_REPO="AvengeMedia/DankMaterialShell"
        info "Downloading pre-built binaries and source for dms..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.5.2ppa1 -> 0.5.2, Quilt: 0.5.2-1ppa1 -> 0.5.2
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download amd64 binary (will be included in source package)
        if [ ! -f "dms-distropkg-amd64.gz" ]; then
            info "Downloading dms binary for amd64..."
            if wget -O dms-distropkg-amd64.gz "https://github.com/AvengeMedia/DankMaterialShell/releases/download/v${VERSION}/dms-distropkg-amd64.gz"; then
                success "amd64 binary downloaded"
            else
                error "Failed to download dms-distropkg-amd64.gz"
                exit 1
            fi
        fi

        # Download source tarball for QML files
        if [ ! -f "dms-source.tar.gz" ]; then
            info "Downloading dms source for QML files..."
            if wget -O dms-source.tar.gz "https://github.com/AvengeMedia/DankMaterialShell/archive/refs/tags/v${VERSION}.tar.gz"; then
                success "source tarball downloaded"
            else
                error "Failed to download dms-source.tar.gz"
                exit 1
            fi
        fi
        ;;
    danksearch)
        # danksearch uses pre-built binary from releases, like dgop
        GIT_REPO="AvengeMedia/danksearch"
        ;;
    matugen)
        GIT_REPO="InioX/matugen"
        ;;
    niri)
        GIT_REPO="YaLTeR/niri"
        ;;
    cliphist)
        GIT_REPO="sentriz/cliphist"
        ;;
    hyprpicker)
        GIT_REPO="hyprwm/hyprpicker"
        info "Downloading dependencies for hyprpicker..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.4.5ppa1 -> 0.4.5, Quilt: 0.4.5-1ppa1 -> 0.4.5
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')
        info "Detected version: $VERSION"

        # Download all required tarballs (Launchpad has no internet access)
        if [ ! -f "pugixml.tar.gz" ]; then
            info "Downloading pugixml v1.14..."
            if wget -q -O pugixml.tar.gz https://github.com/zeux/pugixml/releases/download/v1.14/pugixml-1.14.tar.gz; then
                success "pugixml downloaded"
            else
                error "Failed to download pugixml"
                exit 1
            fi
        fi

        if [ ! -f "hyprutils.tar.gz" ]; then
            info "Downloading hyprutils v0.7.0..."
            if wget -q -O hyprutils.tar.gz https://github.com/hyprwm/hyprutils/archive/refs/tags/v0.7.0.tar.gz; then
                success "hyprutils downloaded"
            else
                error "Failed to download hyprutils"
                exit 1
            fi
        fi

        if [ ! -f "hyprwayland-scanner.tar.gz" ]; then
            info "Downloading hyprwayland-scanner v0.4.2..."
            if wget -q -O hyprwayland-scanner.tar.gz https://github.com/hyprwm/hyprwayland-scanner/archive/refs/tags/v0.4.2.tar.gz; then
                success "hyprwayland-scanner downloaded"
            else
                error "Failed to download hyprwayland-scanner"
                exit 1
            fi
        fi

        if [ ! -f "hyprpicker.tar.gz" ]; then
            info "Downloading hyprpicker v${VERSION}..."
            if wget -q -O hyprpicker.tar.gz https://github.com/hyprwm/hyprpicker/archive/refs/tags/v${VERSION}.tar.gz; then
                success "hyprpicker downloaded"
            else
                error "Failed to download hyprpicker v${VERSION}"
                exit 1
            fi
        fi
        ;;
    dgop)
        # dgop uses pre-built binary from releases
        GIT_REPO="AvengeMedia/dgop"
        ;;
esac

# Handle git packages
if [ "$IS_GIT_PACKAGE" = true ] && [ -n "$GIT_REPO" ]; then
    info "Detected git package: $PACKAGE_NAME"
    
    # Determine source directory name
    if [ -z "$SOURCE_DIR" ]; then
        # Default: use package name without -git suffix + -source or -repo
        BASE_NAME=$(echo "$PACKAGE_NAME" | sed 's/-git$//')
        if [ -d "${BASE_NAME}-source" ] 2>/dev/null; then
            SOURCE_DIR="${BASE_NAME}-source"
        elif [ -d "${BASE_NAME}-repo" ] 2>/dev/null; then
            SOURCE_DIR="${BASE_NAME}-repo"
        elif [ -d "$BASE_NAME" ] 2>/dev/null; then
            SOURCE_DIR="$BASE_NAME"
        else
            SOURCE_DIR="${BASE_NAME}-source"
        fi
    fi
    
    # Always clone fresh source to get latest commit info
    info "Cloning $GIT_REPO from GitHub (getting latest commit info)..."
    TEMP_CLONE=$(mktemp -d)
    if git clone "https://github.com/$GIT_REPO.git" "$TEMP_CLONE"; then
        # Get git commit info from fresh clone
        GIT_COMMIT_HASH=$(cd "$TEMP_CLONE" && git rev-parse --short HEAD)
        GIT_COMMIT_COUNT=$(cd "$TEMP_CLONE" && git rev-list --count HEAD)
        
        # Get upstream version from latest git tag (e.g., 0.2.1)
        # Sort all tags by version and get the latest one (not just the one reachable from HEAD)
        UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l "v*" | sed 's/^v//' | sort -V | tail -1)
        if [ -z "$UPSTREAM_VERSION" ]; then
            # Fallback: try without v prefix
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
        fi
        if [ -z "$UPSTREAM_VERSION" ]; then
            # Last resort: use git describe
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.1")
        fi
        
        # Verify we got valid commit info
        if [ -z "$GIT_COMMIT_COUNT" ] || [ "$GIT_COMMIT_COUNT" = "0" ]; then
            error "Failed to get commit count from $GIT_REPO"
            rm -rf "$TEMP_CLONE"
            exit 1
        fi
        
        if [ -z "$GIT_COMMIT_HASH" ]; then
            error "Failed to get commit hash from $GIT_REPO"
            rm -rf "$TEMP_CLONE"
            exit 1
        fi
        
        success "Got commit info: $GIT_COMMIT_COUNT ($GIT_COMMIT_HASH), upstream: $UPSTREAM_VERSION"
        
        # Update changelog with git commit info
        info "Updating changelog with git commit info..."
        # Format: 0.2.1+git705.fdbb86appa1
        # Check if we're rebuilding the same commit (increment PPA number if so)
        BASE_VERSION="${UPSTREAM_VERSION}+git${GIT_COMMIT_COUNT}.${GIT_COMMIT_HASH}"
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        PPA_NUM=1
        
        # If current version matches the base version, increment PPA number
        # Escape special regex characters in BASE_VERSION for pattern matching
        ESCAPED_BASE=$(echo "$BASE_VERSION" | sed 's/\./\\./g' | sed 's/+/\\+/g')
        if [[ "$CURRENT_VERSION" =~ ^${ESCAPED_BASE}ppa([0-9]+)$ ]]; then
            PPA_NUM=$((BASH_REMATCH[1] + 1))
            info "Detected rebuild of same commit (current: $CURRENT_VERSION), incrementing PPA number to $PPA_NUM"
        else
            info "New commit or first build, using PPA number $PPA_NUM"
        fi
        
        NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        
        # Use sed to update changelog (non-interactive, faster)
        # Get current changelog content - find the next package header line (starts with package name)
        # Skip the first entry entirely by finding the second occurrence of the package name at start of line
        OLD_ENTRY_START=$(grep -n "^${SOURCE_NAME} (" debian/changelog | sed -n '2p' | cut -d: -f1)
        if [ -n "$OLD_ENTRY_START" ]; then
            # Found second entry, use everything from there
            CHANGELOG_CONTENT=$(tail -n +$OLD_ENTRY_START debian/changelog)
        else
            # No second entry found, changelog will only have new entry
            CHANGELOG_CONTENT=""
        fi
        
        # Create new changelog entry with proper format
        CHANGELOG_ENTRY="${SOURCE_NAME} (${NEW_VERSION}) ${UBUNTU_SERIES}; urgency=medium

  * Git snapshot (commit ${GIT_COMMIT_COUNT}: ${GIT_COMMIT_HASH})

 -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
        
        # Write new changelog (new entry, blank line, then old entries)
        echo "$CHANGELOG_ENTRY" > debian/changelog
        if [ -n "$CHANGELOG_CONTENT" ]; then
            echo "" >> debian/changelog
            echo "$CHANGELOG_CONTENT" >> debian/changelog
        fi
        success "Version updated to $NEW_VERSION"
        
        # Now clone to source directory (without .git for inclusion in package)
        rm -rf "$SOURCE_DIR"
        cp -r "$TEMP_CLONE" "$SOURCE_DIR"
        rm -rf "$SOURCE_DIR/.git"
        rm -rf "$TEMP_CLONE"

        # Vendor Rust dependencies for packages that need it
        if [ "$PACKAGE_NAME" = "niri-git" ] || [ "$PACKAGE_NAME" = "quickshell-git" ]; then
            if [ -f "$SOURCE_DIR/Cargo.toml" ]; then
                info "Vendoring Rust dependencies (Launchpad has no internet access)..."
                cd "$SOURCE_DIR"

                # Clean up any existing vendor directory and .orig files
                # (prevents cargo from including .orig files in checksums)
                rm -rf vendor .cargo
                find . -type f -name "*.orig" -exec rm -f {} + || true

                # Download all dependencies (crates.io + git repos) to vendor/
                # cargo vendor outputs the config to stderr, capture it
                mkdir -p .cargo
                cargo vendor 2>&1 | awk '
                    /^\[source\.crates-io\]/ { printing=1 }
                    printing { print }
                    /^directory = "vendor"$/ { exit }
                ' > .cargo/config.toml

                # Verify vendor directory was created
                if [ ! -d "vendor" ]; then
                    error "Failed to vendor dependencies"
                    exit 1
                fi

                # Verify config was created
                if [ ! -s .cargo/config.toml ]; then
                    error "Failed to create cargo config"
                    exit 1
                fi

                # CRITICAL: Remove ALL .orig files from vendor directory
                # These break cargo checksums when dh_clean tries to use them
                info "Cleaning .orig files from vendor directory..."
                find vendor -type f -name "*.orig" -exec rm -fv {} + || true
                find vendor -type f -name "*.rej" -exec rm -fv {} + || true

                # Verify no .orig files remain
                ORIG_COUNT=$(find vendor -type f -name "*.orig" | wc -l)
                if [ "$ORIG_COUNT" -gt 0 ]; then
                    warn "Found $ORIG_COUNT .orig files still in vendor directory"
                fi

                success "Rust dependencies vendored (including git dependencies)"
                cd "$PACKAGE_DIR"
            fi
        fi

        # Download pre-built binary for dms-git
        # dms-git uses latest release binary with git master QML files
        if [ "$PACKAGE_NAME" = "dms-git" ]; then
            info "Downloading latest release binary for dms-git..."
            if [ ! -f "dms-distropkg-amd64.gz" ]; then
                if wget -O dms-distropkg-amd64.gz "https://github.com/AvengeMedia/DankMaterialShell/releases/latest/download/dms-distropkg-amd64.gz"; then
                    success "Latest release binary downloaded"
                else
                    error "Failed to download dms-distropkg-amd64.gz"
                    exit 1
                fi
            else
                info "Release binary already downloaded"
            fi
        fi

        success "Source prepared for packaging"
    else
        error "Failed to clone $GIT_REPO"
        rm -rf "$TEMP_CLONE"
        exit 1
    fi
# Handle stable packages - get latest tag
elif [ -n "$GIT_REPO" ]; then
    info "Detected stable package: $PACKAGE_NAME"
    info "Fetching latest tag from $GIT_REPO..."
    
    LATEST_TAG=$(get_latest_tag "$GIT_REPO")
    if [ -n "$LATEST_TAG" ]; then
        # Check source format - native packages can't use dashes
        SOURCE_FORMAT=$(cat debian/source/format 2>/dev/null | head -1 || echo "3.0 (quilt)")

        # Get current version to check if we need to increment PPA number
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        PPA_NUM=1

        if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
            # Native format: 0.2.1ppa1 (no dash, no revision)
            BASE_VERSION="${LATEST_TAG}"
            # Check if we're rebuilding the same version (increment PPA number if so)
            if [[ "$CURRENT_VERSION" =~ ^${LATEST_TAG}ppa([0-9]+)$ ]]; then
                PPA_NUM=$((BASH_REMATCH[1] + 1))
                info "Detected rebuild of same version (current: $CURRENT_VERSION), incrementing PPA number to $PPA_NUM"
            else
                info "New version or first build, using PPA number $PPA_NUM"
            fi
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        else
            # Quilt format: 0.2.1-1ppa1 (with revision)
            BASE_VERSION="${LATEST_TAG}-1"
            # Check if we're rebuilding the same version (increment PPA number if so)
            ESCAPED_BASE=$(echo "$BASE_VERSION" | sed 's/\./\\./g' | sed 's/-/\\-/g')
            if [[ "$CURRENT_VERSION" =~ ^${ESCAPED_BASE}ppa([0-9]+)$ ]]; then
                PPA_NUM=$((BASH_REMATCH[1] + 1))
                info "Detected rebuild of same version (current: $CURRENT_VERSION), incrementing PPA number to $PPA_NUM"
            else
                info "New version or first build, using PPA number $PPA_NUM"
            fi
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        fi

        # Check if version needs updating (either new version or PPA number changed)
        if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
            if [ "$PPA_NUM" -gt 1 ]; then
                info "Updating changelog for rebuild (PPA number incremented to $PPA_NUM)"
            else
                info "Updating changelog to latest tag: $LATEST_TAG"
            fi
            # Use sed to update changelog (non-interactive)
            # Get current changelog content - find the next package header line
            OLD_ENTRY_START=$(grep -n "^${SOURCE_NAME} (" debian/changelog | sed -n '2p' | cut -d: -f1)
            if [ -n "$OLD_ENTRY_START" ]; then
                CHANGELOG_CONTENT=$(tail -n +$OLD_ENTRY_START debian/changelog)
            else
                CHANGELOG_CONTENT=""
            fi
            
            # Create appropriate changelog message
            if [ "$PPA_NUM" -gt 1 ]; then
                CHANGELOG_MSG="Rebuild for packaging fixes (ppa${PPA_NUM})"
            else
                CHANGELOG_MSG="Upstream release ${LATEST_TAG}"
            fi

            CHANGELOG_ENTRY="${SOURCE_NAME} (${NEW_VERSION}) ${UBUNTU_SERIES}; urgency=medium

  * ${CHANGELOG_MSG}

 -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
            echo "$CHANGELOG_ENTRY" > debian/changelog
            if [ -n "$CHANGELOG_CONTENT" ]; then
                echo "" >> debian/changelog
                echo "$CHANGELOG_CONTENT" >> debian/changelog
            fi
            success "Version updated to $NEW_VERSION"
        else
            info "Version already at latest tag: $LATEST_TAG"
        fi
    else
        warn "Could not determine latest tag for $GIT_REPO, using existing version"
    fi
fi

# Handle packages that need pre-built binaries downloaded
cd "$PACKAGE_DIR"
case "$PACKAGE_NAME" in
    danksearch)
        info "Downloading pre-built binaries for danksearch..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.5.2ppa1 -> 0.5.2, Quilt: 0.5.2-1ppa1 -> 0.5.2
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download both amd64 and arm64 binaries (will be included in source package)
        # Launchpad can't download during build, so we include both architectures
        if [ ! -f "dsearch-amd64" ]; then
            info "Downloading dsearch binary for amd64..."
            if wget -O dsearch-amd64.gz "https://github.com/AvengeMedia/danksearch/releases/download/v${VERSION}/dsearch-linux-amd64.gz"; then
                gunzip dsearch-amd64.gz
                chmod +x dsearch-amd64
                success "amd64 binary downloaded"
            else
                error "Failed to download dsearch-amd64.gz"
                exit 1
            fi
        fi

        if [ ! -f "dsearch-arm64" ]; then
            info "Downloading dsearch binary for arm64..."
            if wget -O dsearch-arm64.gz "https://github.com/AvengeMedia/danksearch/releases/download/v${VERSION}/dsearch-linux-arm64.gz"; then
                gunzip dsearch-arm64.gz
                chmod +x dsearch-arm64
                success "arm64 binary downloaded"
            else
                error "Failed to download dsearch-arm64.gz"
                exit 1
            fi
        fi
        ;;
    dgop)
        # dgop binary should already be committed in the repo
        if [ ! -f "dgop" ]; then
            warn "dgop binary not found - should be committed to repo"
        fi
        ;;
    cliphist)
        info "Preparing cliphist source with vendored dependencies..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.5.2ppa1 -> 0.5.2, Quilt: 0.5.2-1ppa1 -> 0.5.2
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download and vendor Go dependencies (Launchpad has no internet access)
        if [ ! -f "cliphist.tar.gz" ] || [ ! -d "cliphist-${VERSION}/vendor" ]; then
            info "Downloading cliphist source tarball v${VERSION}..."
            wget -O cliphist-download.tar.gz "https://github.com/sentriz/cliphist/archive/refs/tags/v${VERSION}.tar.gz"

            info "Extracting and vendoring Go dependencies..."
            rm -rf cliphist-${VERSION}
            tar -xzf cliphist-download.tar.gz
            rm -f cliphist-download.tar.gz

            cd cliphist-${VERSION}
            if [ -f go.mod ]; then
                go mod download
                go mod vendor
                success "Go dependencies vendored"
            fi
            cd ..

            # Repackage with vendor directory
            tar -czf cliphist.tar.gz cliphist-${VERSION}
            success "Source tarball created with vendored dependencies"
        else
            info "Vendored source tarball already exists"
        fi
        ;;
    matugen)
        info "Downloading pre-built binaries and source for matugen..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.5.2ppa1 -> 0.5.2, Quilt: 0.5.2-1ppa1 -> 0.5.2
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download amd64 binary (will be included in source package)
        if [ ! -f "matugen-amd64.tar.gz" ]; then
            info "Downloading matugen binary for amd64..."
            if wget -O matugen-amd64.tar.gz "https://github.com/InioX/matugen/releases/download/v${VERSION}/matugen-${VERSION}-x86_64.tar.gz"; then
                success "amd64 binary downloaded"
            else
                error "Failed to download matugen-amd64.tar.gz"
                exit 1
            fi
        fi

        # Download source for arm64 (to build with cargo)
        if [ ! -f "matugen-source.tar.gz" ]; then
            info "Downloading matugen source for arm64..."
            if wget -O matugen-source.tar.gz "https://github.com/InioX/matugen/archive/refs/tags/v${VERSION}.tar.gz"; then
                success "arm64 source downloaded"
            else
                error "Failed to download matugen-source.tar.gz"
                exit 1
            fi
        fi
        ;;
    niri)
        info "Preparing niri source with vendored dependencies..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.1.10ppa1 -> 0.1.10, Quilt: 0.1.10-1ppa1 -> 0.1.10
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download and vendor Rust dependencies (Launchpad has no internet access)
        if [ ! -d "niri-${VERSION}/vendor" ]; then
            info "Downloading niri source tarball v${VERSION}..."
            if wget -O niri-download.tar.gz "https://github.com/YaLTeR/niri/archive/refs/tags/v${VERSION}.tar.gz"; then
                info "Extracting and vendoring Rust dependencies..."
                rm -rf "niri-${VERSION}"
                tar -xzf niri-download.tar.gz
                rm -f niri-download.tar.gz

                cd "niri-${VERSION}"
                if [ -f Cargo.toml ]; then
                    # Clean up any existing vendor directory
                    rm -rf vendor .cargo
                    find . -type f -name "*.orig" -exec rm -f {} + || true

                    # Download all dependencies (crates.io + git repos) to vendor/
                    mkdir -p .cargo
                    cargo vendor 2>&1 | awk '
                        /^\[source\.crates-io\]/ { printing=1 }
                        printing { print }
                        /^directory = "vendor"$/ { exit }
                    ' > .cargo/config.toml

                    # Verify vendor directory was created
                    if [ ! -d "vendor" ]; then
                        error "Failed to vendor dependencies"
                        exit 1
                    fi

                    # Remove ALL .orig files from vendor directory
                    info "Cleaning .orig files from vendor directory..."
                    find vendor -type f -name "*.orig" -exec rm -fv {} + || true
                    find vendor -type f -name "*.rej" -exec rm -fv {} + || true

                    success "Rust dependencies vendored"
                else
                    error "Cargo.toml not found in niri-${VERSION}"
                    exit 1
                fi
                cd ..
            else
                error "Failed to download niri source"
                exit 1
            fi
        else
            info "Vendored source already exists"
        fi
        ;;
esac

cd - > /dev/null

# Build source package
info "Building source package..."
echo

# Use -S for source only, -sa to include original source
# -d skips dependency checking (we're building on Fedora, not Ubuntu)
# Pipe yes to automatically answer prompts (e.g., "continue anyway?")
if yes | DEBIAN_FRONTEND=noninteractive debuild -S -sa -d; then
    echo
    success "Source package built successfully!"

    # Clean up extracted source directories (they're included in .tar.xz)
    cd "$PACKAGE_DIR"
    case "$PACKAGE_NAME" in
        niri-git)
            info "Cleaning up extracted source directory..."
            rm -rf niri
            ;;
        quickshell-git)
            info "Cleaning up extracted source directory..."
            rm -rf quickshell-source quickshell
            ;;
        dms-git)
            info "Cleaning up extracted source directory..."
            rm -rf dms-git-repo
            ;;
        niri)
            info "Cleaning up extracted source directory..."
            rm -rf niri-[0-9]*.[0-9]*.[0-9]*
            ;;
        cliphist)
            info "Cleaning up extracted source directory..."
            rm -rf cliphist-[0-9]*.[0-9]*.[0-9]*
            ;;
    esac
    cd - > /dev/null

    # List generated files
    info "Generated files in $(dirname "$PACKAGE_DIR"):"
    ls -lh "$(dirname "$PACKAGE_DIR")"/${SOURCE_NAME}_${CHANGELOG_VERSION}* 2>/dev/null || true

    # Show what to do next
    echo
    info "Next steps:"
    echo "  1. Review the source package:"
    echo "     cd $(dirname "$PACKAGE_DIR")"
    echo "     ls -lh ${SOURCE_NAME}_${CHANGELOG_VERSION}*"
    echo
    echo "  2. Upload to PPA (stable):"
    echo "     dput ppa:avengemedia/dms ${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes"
    echo
    echo "  3. Or upload to PPA (nightly):"
    echo "     dput ppa:avengemedia/dms-git ${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes"
    echo
    echo "  4. Or use the upload script:"
    echo "     ./common/upload-ppa.sh $(dirname "$PACKAGE_DIR")/${SOURCE_NAME}_${CHANGELOG_VERSION}_source.changes dms"

else
    error "Source package build failed!"
    exit 1
fi
