#!/bin/bash
# Unified PPA build and upload script for danklinux packages
# Builds source package and uploads to Launchpad PPA
# Usage: ./ppa-upload.sh [package-name] [ppa-name] [ubuntu-series] [rebuild-number] [--keep-builds] [--build-only]
#
# Examples:
#   ./ppa-upload.sh                           # Interactive menu
#   ./ppa-upload.sh ghostty                   # Single package
#   ./ppa-upload.sh all                       # All packages
#   ./ppa-upload.sh ghostty danklinux questing --build-only
#   ./ppa-upload.sh niri-git 2                # Rebuild with ppa2 suffix
#   ./ppa-upload.sh niri-git --rebuild=2      # Rebuild with ppa2 suffix (flag syntax)

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

# Choose temp directory: use /tmp in CI, ~/tmp locally (keeps artifacts out of repo)
if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
    TEMP_BASE="/tmp"
else
    TEMP_BASE="$HOME/tmp"
    mkdir -p "$TEMP_BASE"
fi

TEMP_DIR=$(mktemp -d "$TEMP_BASE/ppa_build_XXXXXX")
trap "rm -rf $TEMP_DIR" EXIT

AVAILABLE_PACKAGES=(cliphist danksearch dgop ghostty matugen niri niri-git quickshell quickshell-git xwayland-satellite xwayland-satellite-git)
KEEP_BUILDS=false
BUILD_ONLY=false
REBUILD_RELEASE=""
POSITIONAL_ARGS=()
REBUILD_NEXT=false

for arg in "$@"; do
    case "$arg" in
        --keep-builds) KEEP_BUILDS=true ;;
        --build-only) BUILD_ONLY=true ;;
        --rebuild=*)
            REBUILD_RELEASE="${arg#*=}"
            ;;
        -r|--rebuild)
            REBUILD_NEXT=true
            ;;
        *)
            if [[ "${REBUILD_NEXT:-false}" == "true" ]]; then
                REBUILD_RELEASE="$arg"
                REBUILD_NEXT=false
            else
                POSITIONAL_ARGS+=("$arg")
            fi
            ;;
    esac
done

PACKAGE="${POSITIONAL_ARGS[0]:-}"
PPA_NAME="${POSITIONAL_ARGS[1]:-danklinux}"
UBUNTU_SERIES="${POSITIONAL_ARGS[2]:-questing}"

# Check if last positional argument is a number (rebuild release)
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    LAST_INDEX=$((${#POSITIONAL_ARGS[@]} - 1))
    LAST_ARG="${POSITIONAL_ARGS[$LAST_INDEX]}"
    if [[ "$LAST_ARG" =~ ^[0-9]+$ ]] && [[ -z "$REBUILD_RELEASE" ]]; then
        # Last argument is a number and no --rebuild flag was used
        # Use it as rebuild release and remove from positional args
        REBUILD_RELEASE="$LAST_ARG"
        POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:0:$LAST_INDEX}")
        # Re-assign variables after slicing array
        PACKAGE="${POSITIONAL_ARGS[0]:-}"
        PPA_NAME="${POSITIONAL_ARGS[1]:-danklinux}"
        UBUNTU_SERIES="${POSITIONAL_ARGS[2]:-questing}"
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -d "$REPO_ROOT/distro/ubuntu" ]]; then
    error "Cannot find distro/ubuntu directory. Run from repository root."
    exit 1
fi

# Support both path-style and name-style arguments
if [[ -n "$PACKAGE" ]] && [[ "$PACKAGE" == *"/"* ]]; then
    if [[ -d "$PACKAGE" ]]; then
        PACKAGE_DIR="$(cd "$PACKAGE" && pwd)"
    elif [[ -d "$REPO_ROOT/$PACKAGE" ]]; then
        PACKAGE_DIR="$(cd "$REPO_ROOT/$PACKAGE" && pwd)"
    else
        error "Package directory not found: $PACKAGE"
        exit 1
    fi
    PACKAGE=$(basename "$PACKAGE_DIR")
    info "Using path-style argument: $PACKAGE_DIR"
fi

if [[ -z "$PACKAGE" ]]; then
    echo "Available packages:"
    echo ""
    for i in "${!AVAILABLE_PACKAGES[@]}"; do
        echo "  $((i+1)). ${AVAILABLE_PACKAGES[$i]}"
    done
    echo "  a. all"
    echo ""
    read -p "Select package (1-${#AVAILABLE_PACKAGES[@]}, a): " selection
    
    if [[ "$selection" == "a" ]] || [[ "$selection" == "all" ]]; then
        PACKAGE="all"
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#AVAILABLE_PACKAGES[@]} ]]; then
        PACKAGE="${AVAILABLE_PACKAGES[$((selection-1))]}"
    else
        error "Invalid selection"
        exit 1
    fi
fi

if [[ "$PACKAGE" == "all" ]]; then
    echo ""
    info "Building and uploading all packages..."
    FAILED_PACKAGES=()
    for pkg in "${AVAILABLE_PACKAGES[@]}"; do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "Processing $pkg..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        BUILD_ARGS=("$pkg" "$PPA_NAME" "$UBUNTU_SERIES")
        [[ "$KEEP_BUILDS" == "true" ]] && BUILD_ARGS+=("--keep-builds")
        [[ "$BUILD_ONLY" == "true" ]] && BUILD_ARGS+=("--build-only")
        if ! "$0" "${BUILD_ARGS[@]}"; then
            FAILED_PACKAGES+=("$pkg")
            error "$pkg failed to upload"
        fi
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ ${#FAILED_PACKAGES[@]} -eq 0 ]]; then
        success "All packages uploaded successfully!"
    else
        error "Some packages failed: ${FAILED_PACKAGES[*]}"
        exit 1
    fi
    exit 0
fi

VALID_PACKAGE=false
for pkg in "${AVAILABLE_PACKAGES[@]}"; do
    if [[ "$PACKAGE" == "$pkg" ]]; then
        VALID_PACKAGE=true
        break
    fi
done

if [[ "$VALID_PACKAGE" != "true" ]]; then
    error "Unknown package: $PACKAGE"
    echo "Available packages: ${AVAILABLE_PACKAGES[*]}"
    exit 1
fi

if [[ -z "${PACKAGE_DIR:-}" ]]; then
    PACKAGE_DIR="$REPO_ROOT/distro/ubuntu/$PACKAGE"
fi
PACKAGE_NAME="$PACKAGE"
OUTPUT_DIR="$(dirname "$PACKAGE_DIR")"
BUILD_DIR="$TEMP_DIR/$PACKAGE_NAME"

if [ ! -d "$PACKAGE_DIR" ]; then
    error "Package directory not found: $PACKAGE_DIR"
    exit 1
fi

if [ ! -d "$PACKAGE_DIR/debian" ]; then
    error "No debian/ directory found in $PACKAGE_DIR"
    exit 1
fi

info "Building source package for: $PACKAGE_NAME"
info "Package directory: $PACKAGE_DIR"
info "Build directory: $BUILD_DIR"
info "Output directory: $OUTPUT_DIR"
info "Target Ubuntu series: $UBUNTU_SERIES"

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

info "Checking GPG key setup..."
if ! gpg --list-secret-keys &> /dev/null; then
    error "No GPG secret keys found. Please set up GPG first!"
    error "See GPG_SETUP.md for instructions"
    exit 1
fi

success "GPG key found"

if ! command -v debuild &> /dev/null; then
    error "debuild not found. Install devscripts:"
    error "  sudo dnf install devscripts"
    exit 1
fi

mkdir -p "$BUILD_DIR"
cp -r "$PACKAGE_DIR/debian" "$BUILD_DIR/"

cd "$BUILD_DIR"
CHANGELOG_VERSION=$(dpkg-parsechangelog -S Version)
SOURCE_NAME=$(dpkg-parsechangelog -S Source)

info "Source package: $SOURCE_NAME"
info "Version: $CHANGELOG_VERSION"

# Native format requires directory named {source}-{version}
VERSION_FOR_DIR=$(echo "$CHANGELOG_VERSION" | sed 's/~.*//; s/+.*//')
PROPER_BUILD_DIR="$TEMP_DIR/${SOURCE_NAME}-${VERSION_FOR_DIR}"
if [ "$BUILD_DIR" != "$PROPER_BUILD_DIR" ]; then
    mv "$BUILD_DIR" "$PROPER_BUILD_DIR"
    BUILD_DIR="$PROPER_BUILD_DIR"
    cd "$BUILD_DIR"
    info "Build directory renamed to: $BUILD_DIR"
fi

CHANGELOG_SERIES=$(dpkg-parsechangelog -S Distribution)
if [ "$CHANGELOG_SERIES" != "$UBUNTU_SERIES" ] && [ "$CHANGELOG_SERIES" != "UNRELEASED" ]; then
    warn "Changelog targets '$CHANGELOG_SERIES' but building for '$UBUNTU_SERIES'"
    warn "Consider updating changelog with: dch -r '' -D $UBUNTU_SERIES"
fi

cd "$BUILD_DIR"

get_latest_tag() {
    local repo="$1"
    if command -v curl &> /dev/null; then
        LATEST_TAG=$(curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | grep '"tag_name":' | sed 's/.*"tag_name": "\(.*\)".*/\1/' | head -1)
        if [ -n "$LATEST_TAG" ]; then
            echo "$LATEST_TAG" | sed 's/^v//'
            return
        fi
    fi
    TEMP_REPO=$(mktemp -d "$TEMP_BASE/ppa_tag_XXXXXX")
    if git clone --depth=1 --quiet "https://github.com/$repo.git" "$TEMP_REPO" 2>/dev/null; then
        LATEST_TAG=$(cd "$TEMP_REPO" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
        rm -rf "$TEMP_REPO"
        echo "$LATEST_TAG"
    fi
}

IS_GIT_PACKAGE=false
GIT_REPO=""
SOURCE_DIR=""
if [[ "$PACKAGE_NAME" == *"-git" ]]; then
    IS_GIT_PACKAGE=true
fi

if grep -q "git clone" debian/rules 2>/dev/null; then
    IS_GIT_PACKAGE=true
    # Extract GitHub repo URL from rules
    GIT_URL=$(grep -o "git clone.*https://github.com/[^/]*/[^/]*\.git" debian/rules 2>/dev/null | head -1 | sed 's/.*github\.com\///' | sed 's/\.git.*//' || echo "")
    if [ -n "$GIT_URL" ]; then
        GIT_REPO="$GIT_URL"
    fi
fi

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
    danksearch)
        # danksearch uses pre-built binary releases
        GIT_REPO="AvengeMedia/danksearch"
        ;;
    matugen)
        GIT_REPO="InioX/matugen"
        ;;
    niri)
        GIT_REPO="YaLTeR/niri"
        ;;
    quickshell)
        GIT_REPO="quickshell-mirror/quickshell"
        ;;
    xwayland-satellite)
        GIT_REPO="Supreeeme/xwayland-satellite"
        ;;
    xwayland-satellite-git)
        IS_GIT_PACKAGE=true
        GIT_REPO="Supreeeme/xwayland-satellite"
        SOURCE_DIR="xwayland-satellite-source"
        ;;
    cliphist)
        GIT_REPO="sentriz/cliphist"
        ;;
    dgop)
        # dgop uses pre-built binary from releases
        GIT_REPO="AvengeMedia/dgop"
        ;;
    ghostty)
        FORCE_SA="true"
        
        # Handle version bumping for rebuilds
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        if [ -n "${REBUILD_RELEASE:-}" ] && [ -n "$CURRENT_VERSION" ]; then
            # Extract base version (everything before ppa)
            BASE_VERSION=$(echo "$CURRENT_VERSION" | sed 's/ppa[0-9]*$//')
            NEW_VERSION="${BASE_VERSION}ppa${REBUILD_RELEASE}"
            
            if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
                info "Updating version: $CURRENT_VERSION -> $NEW_VERSION"
                
                # Update changelog
                TIMESTAMP=$(date -R)
                MAINTAINER=$(dpkg-parsechangelog -S Maintainer)
                DISTRIBUTION=$(dpkg-parsechangelog -S Distribution)
                
                cat > debian/changelog.new << EOF
$PACKAGE_NAME ($NEW_VERSION) $DISTRIBUTION; urgency=medium

  * Rebuild: Update Zig dependencies for offline builds

 -- $MAINTAINER  $TIMESTAMP

EOF
                cat debian/changelog >> debian/changelog.new
                mv debian/changelog.new debian/changelog
                
                success "Changelog updated to version $NEW_VERSION"
            fi
        fi
        
        info "Running Ghostty source update script..."
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')
        if "$PACKAGE_DIR/update-source.sh" "$VERSION"; then
            success "Ghostty source updated"
            
            # Copy generated orig tarball to temp dir where build happens
            # update-source.sh places it in PACKAGE_DIR/..
            ORIG_TARBALL="${PACKAGE_NAME}_${VERSION}.orig.tar.xz"
            if [ -f "$PACKAGE_DIR/../$ORIG_TARBALL" ]; then
                cp "$PACKAGE_DIR/../$ORIG_TARBALL" "$TEMP_DIR/"
                success "Copied $ORIG_TARBALL to build directory"
                
                # For native format, extract the source into the build directory
                # Native packages the entire build dir, not a separate tarball
                info "Extracting source for native format packaging..."
                cd "$BUILD_DIR"
                tar -xf "$TEMP_DIR/$ORIG_TARBALL" --strip-components=1
                success "Source extracted to build directory"
            else
                error "Generated tarball not found at $PACKAGE_DIR/../$ORIG_TARBALL"
                exit 1
            fi
        else
            error "Failed to update Ghostty source"
            exit 1
        fi
        ;;
esac

if [ "$IS_GIT_PACKAGE" = true ] && [ -n "$GIT_REPO" ]; then
    info "Detected git package: $PACKAGE_NAME"
    
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
    
    info "Cloning $GIT_REPO from GitHub (getting latest commit info)..."
    TEMP_CLONE=$(mktemp -d "$TEMP_BASE/ppa_clone_XXXXXX")
    if git clone "https://github.com/$GIT_REPO.git" "$TEMP_CLONE"; then
        GIT_COMMIT_HASH=$(cd "$TEMP_CLONE" && git rev-parse --short HEAD)
        GIT_COMMIT_COUNT=$(cd "$TEMP_CLONE" && git rev-list --count HEAD)
        
        UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l "v*" | sed 's/^v//' | sort -V | tail -1)
        if [ -z "$UPSTREAM_VERSION" ]; then
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
        fi
        if [ -z "$UPSTREAM_VERSION" ]; then
            UPSTREAM_VERSION=$(cd "$TEMP_CLONE" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.1")
        fi
        
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
        
        info "Updating changelog with git commit info..."
        BASE_VERSION="${UPSTREAM_VERSION}+git${GIT_COMMIT_COUNT}.${GIT_COMMIT_HASH}"
        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        PPA_NUM=1
        
        # If current version matches the base version, increment PPA number
        ESCAPED_BASE=$(echo "$BASE_VERSION" | sed 's/\./\\./g' | sed 's/+/\\+/g')
        
        if [ -n "${REBUILD_RELEASE:-}" ]; then
            PPA_NUM=$REBUILD_RELEASE
            info "🔄 Using manual rebuild release number: ppa$PPA_NUM"
        elif [[ "$CURRENT_VERSION" =~ ^${ESCAPED_BASE}ppa([0-9]+)$ ]]; then
            # In CI, skip if same version (no new commits)
            if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
                info "Same commit detected in CI (current: $CURRENT_VERSION), skipping build"
                exit 0
            fi
            error "Same commit detected ($CURRENT_VERSION) but no rebuild number specified"
            error "To rebuild, explicitly specify a rebuild number:"
            error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 2"
            error "or use flag syntax:"
            error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME --rebuild=2"
            exit 1
        else
            info "New commit or first build, using PPA number $PPA_NUM"
        fi
        
        NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        
        OLD_ENTRY_START=$(grep -n "^${SOURCE_NAME} (" debian/changelog | sed -n '2p' | cut -d: -f1)
        if [ -n "$OLD_ENTRY_START" ]; then
            CHANGELOG_CONTENT=$(tail -n +$OLD_ENTRY_START debian/changelog)
        else
            CHANGELOG_CONTENT=""
        fi
        
        # Create new changelog entry with proper format
        CHANGELOG_ENTRY="${SOURCE_NAME} (${NEW_VERSION}) ${UBUNTU_SERIES}; urgency=medium

  * Git snapshot (commit ${GIT_COMMIT_COUNT}: ${GIT_COMMIT_HASH})

 -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
        
        echo "$CHANGELOG_ENTRY" > debian/changelog
        if [ -n "$CHANGELOG_CONTENT" ]; then
            echo "" >> debian/changelog
            echo "$CHANGELOG_CONTENT" >> debian/changelog
        fi
        success "Version updated to $NEW_VERSION"
        
        # Write changelog back to original package directory
        info "Writing updated changelog back to repository..."
        cp debian/changelog "$PACKAGE_DIR/debian/changelog"
        success "Changelog written back to $PACKAGE_DIR/debian/changelog"
        
        rm -rf "$SOURCE_DIR"
        cp -r "$TEMP_CLONE" "$SOURCE_DIR"
        rm -rf "$SOURCE_DIR/.git"
        rm -rf "$TEMP_CLONE"

        if [ "$PACKAGE_NAME" = "niri-git" ] || [ "$PACKAGE_NAME" = "quickshell-git" ] || [ "$PACKAGE_NAME" = "xwayland-satellite-git" ]; then
            if [ -f "$SOURCE_DIR/Cargo.toml" ]; then
                info "Vendoring Rust dependencies (Launchpad has no internet access)..."
                cd "$SOURCE_DIR"

                rm -rf vendor .cargo
                find . -type f -name "*.orig" -exec rm -f {} + || true

                mkdir -p .cargo
                cargo vendor 2>&1 | awk '
                    /^\[source\.crates-io\]/ { printing=1 }
                    printing { print }
                    /^directory = "vendor"$/ { exit }
                ' > .cargo/config.toml

                if [ ! -d "vendor" ]; then
                    error "Failed to vendor dependencies"
                    exit 1
                fi

                if [ ! -s .cargo/config.toml ]; then
                    error "Failed to create cargo config"
                    exit 1
                fi

                info "Cleaning .orig files from vendor directory..."
                find vendor -type f -name "*.orig" -exec rm -fv {} + || true
                find vendor -type f -name "*.rej" -exec rm -fv {} + || true

                ORIG_COUNT=$(find vendor -type f -name "*.orig" | wc -l)
                if [ "$ORIG_COUNT" -gt 0 ]; then
                    warn "Found $ORIG_COUNT .orig files still in vendor directory"
                fi

                success "Rust dependencies vendored (including git dependencies)"
                cd "$BUILD_DIR"
            fi
        fi

        success "Source prepared for packaging"
    else
        error "Failed to clone $GIT_REPO"
        rm -rf "$TEMP_CLONE"
        exit 1
    fi
elif [ -n "$GIT_REPO" ] && [ "${SKIP_VERSION_UPDATE:-false}" != "true" ]; then
    info "Detected stable package: $PACKAGE_NAME"

    # Check if this is a pinned quickshell version - if so, skip version update
    CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
    if [ "$PACKAGE_NAME" = "quickshell" ]; then
        if [[ "$CURRENT_VERSION" =~ \+pin([0-9]+)\.([a-f0-9]+) ]] || [[ "$CURRENT_VERSION" =~ ~pin([0-9]+)\.([a-f0-9]+) ]]; then
            info "Detected pinned quickshell version ($CURRENT_VERSION), preserving changelog"
            SKIP_VERSION_UPDATE=true
        fi
    fi

    if [ "${SKIP_VERSION_UPDATE:-false}" = "true" ]; then
        info "Skipping version update (manual version in changelog)"
        # In CI, exit early - we don't rebuild pinned versions automatically
        if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
            info "CI run detected with pinned version - skipping upload"
            exit 0
        fi
    else
        info "Fetching latest tag from $GIT_REPO..."
        LATEST_TAG=$(get_latest_tag "$GIT_REPO")
    fi

    if [ -n "$LATEST_TAG" ] && [ "${SKIP_VERSION_UPDATE:-false}" != "true" ]; then
        SOURCE_FORMAT=$(cat debian/source/format 2>/dev/null | head -1 || echo "3.0 (quilt)")

        CURRENT_VERSION=$(dpkg-parsechangelog -S Version 2>/dev/null || echo "")
        PPA_NUM=1

        if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
            BASE_VERSION="${LATEST_TAG}"
            # Check if manual rebuild release number is specified
            if [ -n "${REBUILD_RELEASE:-}" ]; then
                PPA_NUM=$REBUILD_RELEASE
                info "🔄 Using manual rebuild release number: ppa$PPA_NUM"
            elif [[ "$CURRENT_VERSION" =~ ^${LATEST_TAG}ppa([0-9]+)$ ]]; then
                # In CI, skip if same version
                if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
                    info "Same version detected in CI (current: $CURRENT_VERSION), skipping build"
                    exit 0
                fi
                error "Same version detected ($CURRENT_VERSION) but no rebuild number specified"
                error "To rebuild, explicitly specify a rebuild number:"
                error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 2"
                error "or use flag syntax:"
                error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME --rebuild=2"
                exit 1
            else
                info "New version or first build, using PPA number $PPA_NUM"
            fi
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        else
            BASE_VERSION="${LATEST_TAG}-1"
            # Check if manual rebuild release number is specified
            if [ -n "${REBUILD_RELEASE:-}" ]; then
                PPA_NUM=$REBUILD_RELEASE
                info "🔄 Using manual rebuild release number: ppa$PPA_NUM"
            else
                # Check if we're rebuilding the same version
                ESCAPED_BASE=$(echo "$BASE_VERSION" | sed 's/\./\\./g' | sed 's/-/\\-/g')
                if [[ "$CURRENT_VERSION" =~ ^${ESCAPED_BASE}ppa([0-9]+)$ ]]; then
                    # In CI, skip if same version
                    if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${CI:-}" ]; then
                        info "Same version detected in CI (current: $CURRENT_VERSION), skipping build"
                        exit 0
                    fi
                    error "Same version detected ($CURRENT_VERSION) but no rebuild number specified"
                    error "To rebuild, explicitly specify a rebuild number:"
                    error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME 2"
                    error "or use flag syntax:"
                    error "  ./distro/scripts/ppa-upload.sh $PACKAGE_NAME --rebuild=2"
                    exit 1
                else
                    info "New version or first build, using PPA number $PPA_NUM"
                fi
            fi
            NEW_VERSION="${BASE_VERSION}ppa${PPA_NUM}"
        fi

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
            
            # Write changelog back to original package directory
            info "Writing updated changelog back to repository..."
            cp debian/changelog "$PACKAGE_DIR/debian/changelog"
            success "Changelog written back to $PACKAGE_DIR/debian/changelog"
        else
            info "Version already at latest tag: $LATEST_TAG"
        fi
    else
        warn "Could not determine latest tag for $GIT_REPO, using existing version"
    fi
fi

# Handle packages that need pre-built binaries downloaded
cd "$BUILD_DIR"
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
        info "Downloading pre-built binaries for dgop..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        # Native: 0.1.12ppa1 -> 0.1.12, Quilt: 0.1.12-1ppa1 -> 0.1.12
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download both amd64 and arm64 binaries (will be included in source package)
        # Launchpad can't download during build, so we include both architectures
        if [ ! -f "dgop-amd64" ]; then
            info "Downloading dgop binary for amd64..."
            if wget -O dgop-amd64.gz "https://github.com/AvengeMedia/dgop/releases/download/v${VERSION}/dgop-linux-amd64.gz"; then
                gunzip dgop-amd64.gz
                chmod +x dgop-amd64
                success "amd64 binary downloaded"
            else
                error "Failed to download dgop-amd64.gz"
                exit 1
            fi
        fi

        if [ ! -f "dgop-arm64" ]; then
            info "Downloading dgop binary for arm64..."
            if wget -O dgop-arm64.gz "https://github.com/AvengeMedia/dgop/releases/download/v${VERSION}/dgop-linux-arm64.gz"; then
                gunzip dgop-arm64.gz
                chmod +x dgop-arm64
                success "arm64 binary downloaded"
            else
                error "Failed to download dgop-arm64.gz"
                exit 1
            fi
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

        # Download and vendor source for arm64 (Launchpad has no internet access)
        if [ ! -d "matugen-${VERSION}/vendor" ]; then
            info "Downloading matugen source for arm64..."
            if wget -O matugen-download.tar.gz "https://github.com/InioX/matugen/archive/refs/tags/v${VERSION}.tar.gz"; then
                info "Extracting and vendoring Rust dependencies..."
                rm -rf "matugen-${VERSION}"
                tar -xzf matugen-download.tar.gz
                rm -f matugen-download.tar.gz
                
                EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "matugen-*" | grep -v "\.tar\.gz" | head -1)
                if [ -n "$EXTRACTED_DIR" ]; then
                    EXTRACTED_DIR=$(echo "$EXTRACTED_DIR" | sed 's|^\./||')
                    if [ "$EXTRACTED_DIR" != "matugen-${VERSION}" ]; then
                        mv "$EXTRACTED_DIR" "matugen-${VERSION}"
                    fi
                else
                    error "Could not find extracted matugen directory"
                    exit 1
                fi
                
                cd "matugen-${VERSION}"
                if [ -f Cargo.toml ]; then
                    rm -rf vendor .cargo
                    find . -type f -name "*.orig" -exec rm -f {} + || true
                    
                    mkdir -p .cargo
                    cargo vendor 2>&1 | awk '
                        /^\[source\.crates-io\]/ { printing=1 }
                        printing { print }
                        /^directory = "vendor"$/ { exit }
                    ' > .cargo/config.toml
                    
                    if [ ! -d "vendor" ]; then
                        error "Failed to vendor dependencies"
                        exit 1
                    fi
                    
                    find vendor -type f -name "*.orig" -exec rm -fv {} + || true
                    find vendor -type f -name "*.rej" -exec rm -fv {} + || true
                    success "Rust dependencies vendored"
                else
                    error "Cargo.toml not found in matugen-${VERSION}"
                    exit 1
                fi
                cd ..
                
                tar -czf matugen-source.tar.gz "matugen-${VERSION}"
                success "Source tarball created with vendored dependencies"
            else
                error "Failed to download matugen source"
                exit 1
            fi
        else
            info "Vendored source already exists, repackaging..."
            tar -czf matugen-source.tar.gz "matugen-${VERSION}"
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
    quickshell)
        info "Preparing quickshell source..."
        # Get full version from changelog
        FULL_VERSION=$(dpkg-parsechangelog -S Version)

        # Check if this is a pinned version
        if [[ "$FULL_VERSION" =~ \+pin([0-9]+)\.([a-f0-9]+) ]] || [[ "$FULL_VERSION" =~ ~pin([0-9]+)\.([a-f0-9]+) ]]; then
            PINNED_COMMIT="${BASH_REMATCH[2]}"
            info "Detected pinned version with commit: $PINNED_COMMIT"

            # Handle rebuild number for pinned versions
            if [ -n "${REBUILD_RELEASE:-}" ]; then
                BASE_VERSION=$(echo "$FULL_VERSION" | sed 's/ppa[0-9]*$//')
                NEW_VERSION="${BASE_VERSION}ppa${REBUILD_RELEASE}"
                
                if [ "$FULL_VERSION" != "$NEW_VERSION" ]; then
                    info "Updating pinned version rebuild number: $FULL_VERSION -> $NEW_VERSION"
                    
                    TIMESTAMP=$(date -R)
                    MAINTAINER=$(dpkg-parsechangelog -S Maintainer)
                    DISTRIBUTION=$(dpkg-parsechangelog -S Distribution)
                    SOURCE_NAME=$(dpkg-parsechangelog -S Source)
                    
                    OLD_ENTRY_START=$(grep -n "^${SOURCE_NAME} (" debian/changelog | sed -n '2p' | cut -d: -f1)
                    if [ -n "$OLD_ENTRY_START" ]; then
                        CHANGELOG_CONTENT=$(tail -n +$OLD_ENTRY_START debian/changelog)
                    else
                        CHANGELOG_CONTENT=""
                    fi
                    
                    cat > debian/changelog.new << EOF
${SOURCE_NAME} (${NEW_VERSION}) ${DISTRIBUTION}; urgency=medium

  * Rebuild for packaging fixes (ppa${REBUILD_RELEASE})

 -- ${MAINTAINER}  ${TIMESTAMP}

EOF
                    if [ -n "$CHANGELOG_CONTENT" ]; then
                        echo "" >> debian/changelog.new
                        echo "$CHANGELOG_CONTENT" >> debian/changelog.new
                    fi
                    mv debian/changelog.new debian/changelog
                    cp debian/changelog "$PACKAGE_DIR/debian/changelog"
                    FULL_VERSION="$NEW_VERSION"
                    success "Changelog updated to version $NEW_VERSION"
                fi
            fi

            # Extract base version (0.2.1.1+pin713.26531fcppa5 -> 0.2.1.1)
            BASE_VERSION=$(echo "$FULL_VERSION" | sed 's/[+~]pin.*//' | sed 's/ppa[0-9]*$//')

            # Download source from pinned commit
            if [ ! -d "quickshell-source" ]; then
                info "Downloading quickshell source from pinned commit ${PINNED_COMMIT}..."
                FULL_COMMIT_HASH=$(curl -s "https://api.github.com/repos/quickshell-mirror/quickshell/commits/${PINNED_COMMIT}" | grep '"sha":' | head -1 | sed 's/.*"sha": "\(.*\)".*/\1/')
                if [ -z "$FULL_COMMIT_HASH" ]; then
                    error "Failed to get full commit hash for $PINNED_COMMIT"
                    exit 1
                fi

                if wget -O quickshell-download.tar.gz "https://github.com/quickshell-mirror/quickshell/archive/${FULL_COMMIT_HASH}.tar.gz"; then
                    info "Extracting source..."
                    rm -rf quickshell-source
                    mkdir -p quickshell-source
                    tar -xzf quickshell-download.tar.gz --strip-components=1 -C quickshell-source
                    rm -f quickshell-download.tar.gz
                    success "Source prepared for pinned build"
                else
                    error "Failed to download quickshell source from commit $PINNED_COMMIT"
                    exit 1
                fi
            else
                info "Pinned source already exists"
            fi
        else
            # Normal stable release - get version from changelog
            # Native: 0.2.1ppa1 -> 0.2.1, Quilt: 0.2.1-1ppa1 -> 0.2.1
            VERSION=$(echo "$FULL_VERSION" | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

            # Download source tarball from tag
            if [ ! -d "quickshell-${VERSION}" ]; then
                info "Downloading quickshell source tarball v${VERSION}..."
                if wget -O quickshell-download.tar.gz "https://github.com/quickshell-mirror/quickshell/archive/refs/tags/v${VERSION}.tar.gz"; then
                    info "Extracting source..."
                    rm -rf "quickshell-${VERSION}"
                    tar -xzf quickshell-download.tar.gz
                    rm -f quickshell-download.tar.gz
                    success "Source prepared for packaging"
                else
                    error "Failed to download quickshell source"
                    exit 1
                fi
            else
                info "Source already exists"
            fi
        fi
        ;;
    xwayland-satellite)
        info "Preparing xwayland-satellite source with vendored dependencies..."
        # Get version from changelog (remove ppa suffix for both quilt and native formats)
        VERSION=$(dpkg-parsechangelog -S Version | sed 's/-[^-]*$//' | sed 's/ppa[0-9]*$//')

        # Download and vendor Rust dependencies (Launchpad has no internet access)
        if [ ! -d "xwayland-satellite-${VERSION}/vendor" ]; then
            info "Downloading xwayland-satellite source tarball v${VERSION}..."
            if wget -O xwayland-satellite-download.tar.gz "https://github.com/Supreeeme/xwayland-satellite/archive/refs/tags/v${VERSION}.tar.gz"; then
                info "Extracting and vendoring Rust dependencies..."
                rm -rf "xwayland-satellite-${VERSION}"
                tar -xzf xwayland-satellite-download.tar.gz
                rm -f xwayland-satellite-download.tar.gz

                cd "xwayland-satellite-${VERSION}"
                if [ -f Cargo.toml ]; then
                    rm -rf vendor .cargo
                    find . -type f -name "*.orig" -exec rm -f {} + || true

                    mkdir -p .cargo
                    cargo vendor 2>&1 | awk '
                        /^\[source\.crates-io\]/ { printing=1 }
                        printing { print }
                        /^directory = "vendor"$/ { exit }
                    ' > .cargo/config.toml

                    if [ ! -d "vendor" ]; then
                        error "Failed to vendor dependencies"
                        exit 1
                    fi

                    find vendor -type f -name "*.orig" -exec rm -fv {} + || true
                    find vendor -type f -name "*.rej" -exec rm -fv {} + || true

                    success "Rust dependencies vendored"
                else
                    error "Cargo.toml not found in xwayland-satellite-${VERSION}"
                    exit 1
                fi
                cd ..
            else
                error "Failed to download xwayland-satellite source"
                exit 1
            fi
        else
            info "Vendored source already exists"
        fi
        ;;
esac

# Check if this version already exists on PPA (only in CI environment)
if command -v rmadison >/dev/null 2>&1; then
    info "Checking if version already exists on PPA..."
    PPA_VERSION_CHECK=$(rmadison -u ppa:avengemedia/danklinux "$PACKAGE_NAME" 2>/dev/null | grep "$VERSION" || true)
    if [ -n "$PPA_VERSION_CHECK" ]; then
        warn "Version $VERSION already exists on PPA:"
        echo "$PPA_VERSION_CHECK"
        echo
        warn "Skipping upload to avoid duplicate. If this is a rebuild, increment the ppa number."
        # TEMP_DIR cleanup handled by trap
        exit 0
    fi
fi

# Build source package
info "Building source package..."
cd "$BUILD_DIR"
echo

# Determine if we need to include orig tarball (-sa) or just debian changes (-sd)
ORIG_TARBALL="${PACKAGE_NAME}_${VERSION%.ppa*}.orig.tar.xz"
if [ "${FORCE_SA:-false}" = "true" ]; then
    info "Forcing full source upload (-sa)"
    DEBUILD_SOURCE_FLAG="-sa"
elif [ -f "$TEMP_DIR/$ORIG_TARBALL" ]; then
    info "Found existing orig tarball, using -sd (debian changes only)"
    DEBUILD_SOURCE_FLAG="-sd"
else
    info "No existing orig tarball found, using -sa (include original source)"
    DEBUILD_SOURCE_FLAG="-sa"
fi

# Use -S for source only, -sa/-sd for source inclusion
if yes | DEBIAN_FRONTEND=noninteractive debuild -S $DEBUILD_SOURCE_FLAG -d; then
    echo
    success "Source package built successfully!"

    if [ "$PACKAGE_NAME" = "ghostty" ]; then
        info "Verifying zig-deps/ inclusion in source tarball..."
        TARBALL=$(find "$TEMP_DIR" -name "${PACKAGE_NAME}_*.orig.tar.xz" -type f | head -1)
        if [ -n "$TARBALL" ]; then
            if tar -tf "$TARBALL" 2>/dev/null | grep -q "zig-deps/p/"; then
                success "Verified: zig-deps/p/ included in source tarball"
                DEP_COUNT=$(tar -tf "$TARBALL" 2>/dev/null | grep "zig-deps/p/" | grep -c "/build.zig$" || echo "0")
                if [ "$DEP_COUNT" -gt 0 ]; then
                    info "Tarball contains approximately $DEP_COUNT Zig dependencies"
                fi
            else
                error "zig-deps/p/ NOT found in source tarball!"
                error "The tarball will fail to build on Launchpad"
                exit 1
            fi
        else
            warn "Could not find source tarball to verify"
        fi
    fi

    # Find the changes file - re-read version from changelog in case it was updated
    cd "$BUILD_DIR"
    FINAL_VERSION=$(dpkg-parsechangelog -S Version)
    info "Looking for changes file with version: $FINAL_VERSION"
    
    # Debug: list all changes files in TEMP_DIR
    info "Files in TEMP_DIR:"
    ls -la "$TEMP_DIR"/*.changes 2>/dev/null || info "  (no .changes files found)"
    
    CHANGES_FILE=$(find "$TEMP_DIR" -name "${SOURCE_NAME}_${FINAL_VERSION}_source.changes" -type f | head -1)
    if [ -z "$CHANGES_FILE" ]; then
        # Try broader search
        CHANGES_FILE=$(find "$TEMP_DIR" -name "${SOURCE_NAME}_*_source.changes" -type f | head -1)
    fi
    if [ -z "$CHANGES_FILE" ]; then
        error "Changes file not found after build"
        exit 1
    fi

    # Upload to PPA (unless --build-only)
    if [ "$BUILD_ONLY" = "false" ]; then
        echo
        info "==> Uploading to PPA: ppa:avengemedia/$PPA_NAME"
        
        # Get file paths
        CHANGES_BASENAME=$(basename "$CHANGES_FILE")
        DSC_FILE="${CHANGES_BASENAME/_source.changes/.dsc}"
        BUILDINFO="${CHANGES_BASENAME/_source.changes/_source.buildinfo}"
        
        # For quilt format packages, the tarball is .orig.tar.xz with only upstream version
        # Extract upstream version (everything before the dash in debian version)
        UPSTREAM_VERSION=$(echo "$FINAL_VERSION" | sed 's/-[^-]*$//')
        ORIG_TARBALL="${PACKAGE_NAME}_${UPSTREAM_VERSION}.orig.tar.xz"
        
        # Check for tarball (quilt .orig.tar.xz, native .tar.xz, or .tar.gz)
        if [ -f "$TEMP_DIR/$ORIG_TARBALL" ]; then
            UPLOAD_TARBALL="$ORIG_TARBALL"
        elif [ -f "$TEMP_DIR/${CHANGES_BASENAME/_source.changes/.tar.xz}" ]; then
            UPLOAD_TARBALL="${CHANGES_BASENAME/_source.changes/.tar.xz}"
        elif [ -f "$TEMP_DIR/${CHANGES_BASENAME/_source.changes/.tar.gz}" ]; then
            UPLOAD_TARBALL="${CHANGES_BASENAME/_source.changes/.tar.gz}"
        else
            error "Source tarball not found (tried: $ORIG_TARBALL, ${CHANGES_BASENAME/_source.changes/.tar.xz})"
            exit 1
        fi
        
        info "Uploading files:"
        info "  - $CHANGES_BASENAME"
        info "  - $DSC_FILE"
        info "  - $UPLOAD_TARBALL"
        
        # For quilt packages, also need to upload the debian tarball
        DEBIAN_TARBALL="${PACKAGE_NAME}_${FINAL_VERSION}.debian.tar.xz"
        if [ -f "$TEMP_DIR/$DEBIAN_TARBALL" ]; then
            info "  - $DEBIAN_TARBALL"
        fi
        info "  - $BUILDINFO"
        echo
        
        # Use lftp for upload (works on Fedora where dput is broken)
        LFTP_SCRIPT=$(mktemp "$TEMP_BASE/ppa_lftp_XXXXXX")
        
        # Build upload commands
        UPLOAD_COMMANDS="cd ~avengemedia/ubuntu/$PPA_NAME/
lcd $TEMP_DIR
mput $CHANGES_BASENAME
mput $DSC_FILE
mput $UPLOAD_TARBALL"

        if [ -f "$TEMP_DIR/$DEBIAN_TARBALL" ]; then
            UPLOAD_COMMANDS="$UPLOAD_COMMANDS
mput $DEBIAN_TARBALL"
        fi
        
        UPLOAD_COMMANDS="$UPLOAD_COMMANDS
mput $BUILDINFO
bye"
        
        echo "$UPLOAD_COMMANDS" > "$LFTP_SCRIPT"
        
        if lftp -d ftp://anonymous:@ppa.launchpad.net < "$LFTP_SCRIPT"; then
            rm -f "$LFTP_SCRIPT"
            echo
            success "Upload successful!"
            info "Monitor build progress at:"
            echo "  https://launchpad.net/~avengemedia/+archive/ubuntu/$PPA_NAME/+packages"
        else
            rm -f "$LFTP_SCRIPT"
            error "Upload failed!"
            exit 1
        fi
    else
        info "Build-only mode, skipping upload"
    fi

    # Copy build artifacts to output directory (if --keep-builds or --build-only)
    if [ "$KEEP_BUILDS" = "true" ] || [ "$BUILD_ONLY" = "true" ]; then
        info "Copying build artifacts to $OUTPUT_DIR..."
        ARTIFACTS_COPIED=0
        for pattern in "${SOURCE_NAME}_${FINAL_VERSION}.dsc" \
                       "${SOURCE_NAME}_${FINAL_VERSION}.tar.xz" \
                       "${SOURCE_NAME}_${FINAL_VERSION}.tar.gz" \
                       "${SOURCE_NAME}_${FINAL_VERSION}_source.changes" \
                       "${SOURCE_NAME}_${FINAL_VERSION}_source.buildinfo" \
                       "${SOURCE_NAME}_${FINAL_VERSION}_source.build"; do
            for file in "$TEMP_DIR"/$pattern; do
                if [ -f "$file" ]; then
                    cp "$file" "$OUTPUT_DIR/"
                    ARTIFACTS_COPIED=$((ARTIFACTS_COPIED + 1))
                fi
            done
        done
        success "Copied $ARTIFACTS_COPIED artifact(s) to $OUTPUT_DIR"
        info "Build artifacts in: $OUTPUT_DIR"
    fi

    echo
    success "Done!"
    # TEMP_DIR cleanup handled by trap
else
    error "Source package build failed!"
    exit 1
fi