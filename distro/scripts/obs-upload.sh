#!/bin/bash
# Unified OBS upload script for danklinux packages
# Handles Debian and OpenSUSE builds for both x86_64 and aarch64
# Usage: ./distro/scripts/obs-upload.sh [distro] <package-name> [commit-message]
#
# Examples:
#   ./distro/scripts/obs-upload.sh cliphist "Update to v0.7.0"
#   ./distro/scripts/obs-upload.sh debian cliphist
#   ./distro/scripts/obs-upload.sh opensuse niri
#   ./distro/scripts/obs-upload.sh niri-git "Fix cargo vendor config"

set -e

# Parse arguments for distro selection
UPLOAD_DEBIAN=true
UPLOAD_OPENSUSE=true
PACKAGE=""
MESSAGE=""

for arg in "$@"; do
    case "$arg" in
        debian)
            UPLOAD_DEBIAN=true
            UPLOAD_OPENSUSE=false
            ;;
        opensuse)
            UPLOAD_DEBIAN=false
            UPLOAD_OPENSUSE=true
            ;;
        *)
            if [[ -z "$PACKAGE" ]]; then
                PACKAGE="$arg"
            elif [[ -z "$MESSAGE" ]]; then
                MESSAGE="$arg"
            fi
            ;;
    esac
done
PROJECT="danklinux"
OBS_BASE_PROJECT="home:AvengeMedia"
OBS_BASE="$HOME/.cache/osc-checkouts"

# Available packages
AVAILABLE_PACKAGES=(cliphist matugen niri niri-git quickshell-git danksearch dgop)

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
        echo "Error: Invalid selection"
        exit 1
    fi
    
    # Use default message automatically
fi

if [[ -z "$MESSAGE" ]]; then
    MESSAGE="Update packaging"
fi

# Get repo root (2 levels up from distro/scripts/)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

# Ensure we're in repo root
if [[ ! -d "distro/debian" ]]; then
    echo "Error: Run this script from the repository root"
    exit 1
fi

# Handle "all" option
if [[ "$PACKAGE" == "all" ]]; then
    echo "==> Uploading all packages"
    # Build distro argument if specified
    DISTRO_ARG=""
    if [[ "$UPLOAD_DEBIAN" == true && "$UPLOAD_OPENSUSE" == false ]]; then
        DISTRO_ARG="debian"
    elif [[ "$UPLOAD_DEBIAN" == false && "$UPLOAD_OPENSUSE" == true ]]; then
        DISTRO_ARG="opensuse"
    fi
    echo ""
    FAILED=()
    for pkg in "${AVAILABLE_PACKAGES[@]}"; do
        if [[ -d "distro/debian/$pkg" ]]; then
            echo "=========================================="
            echo "Uploading $pkg..."
            echo "=========================================="
            if [[ -n "$DISTRO_ARG" ]]; then
                if bash "$0" "$DISTRO_ARG" "$pkg" "$MESSAGE"; then
                    echo "✅ $pkg uploaded successfully"
                else
                    echo "❌ $pkg failed to upload"
                    FAILED+=("$pkg")
                fi
            else
                if bash "$0" "$pkg" "$MESSAGE"; then
                    echo "✅ $pkg uploaded successfully"
                else
                    echo "❌ $pkg failed to upload"
                    FAILED+=("$pkg")
                fi
            fi
            echo ""
        else
            echo "⚠️  Skipping $pkg (not found in distro/debian/)"
        fi
    done
    
    if [[ ${#FAILED[@]} -eq 0 ]]; then
        echo "✅ All packages uploaded successfully!"
        exit 0
    else
        echo "❌ Some packages failed: ${FAILED[*]}"
        exit 1
    fi
fi

# Check if package exists
if [[ ! -d "distro/debian/$PACKAGE" ]]; then
    echo "Error: Package '$PACKAGE' not found in distro/debian/"
    exit 1
fi

# Construct full project name
OBS_PROJECT="${OBS_BASE_PROJECT}:${PROJECT}"

echo "==> Target: $OBS_PROJECT / $PACKAGE"
echo "==> Message: $MESSAGE"
if [[ "$UPLOAD_DEBIAN" == true && "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distributions: Debian + OpenSUSE"
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    echo "==> Distribution: Debian only"
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distribution: OpenSUSE only"
fi

# Create .obs directory if it doesn't exist
mkdir -p "$OBS_BASE"

# Check out package if not already present
if [[ ! -d "$OBS_BASE/$OBS_PROJECT/$PACKAGE" ]]; then
    echo "Checking out $OBS_PROJECT/$PACKAGE..."
    cd "$OBS_BASE"
    osc co "$OBS_PROJECT/$PACKAGE"
    cd "$REPO_ROOT"
fi

WORK_DIR="$OBS_BASE/$OBS_PROJECT/$PACKAGE"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "==> Preparing $PACKAGE for OBS upload"

# Clean working directory (keep osc metadata)
find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.spec" -o -name "_service" -o -name "*.dsc" \) -delete 2>/dev/null || true

# Get version from changelog
CHANGELOG_VERSION=$(grep -m1 "^$PACKAGE" distro/debian/$PACKAGE/debian/changelog 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "0.1.11-1")

# Determine source format
SOURCE_FORMAT=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")

# Extract version for tarball naming (remove debian revision for native format)
if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
    # For native format, use full version in tarball name
    TARBALL_VERSION="$CHANGELOG_VERSION"
    # Convert version to Debian-safe format (replace - with _ for tarball name)
    TARBALL_VERSION_SAFE=$(echo "$TARBALL_VERSION" | sed 's/-/_/g')
else
    # For quilt format, extract base version (before -)
    if [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
        TARBALL_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/-.*$//')
        TARBALL_VERSION_SAFE="$TARBALL_VERSION"
    else
        TARBALL_VERSION="$CHANGELOG_VERSION"
        TARBALL_VERSION_SAFE="$TARBALL_VERSION"
    fi
fi

# Determine proper tarball name for native format
if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
    # Format 3.0 (native) requires: <package>_<version>.tar.gz
    # Use the version as-is from changelog (Debian allows dashes in version strings for tarball names)
    COMBINED_TARBALL="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
    
    echo "  - Creating combined source tarball for native format: $COMBINED_TARBALL"
    
    SOURCE_DIR=""
    
    # Check _service file to determine how to get source
    if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
        # Parse _service file to get source
        if grep -q "download_url" "distro/debian/$PACKAGE/_service"; then
            # Extract download_url - handle multiple download_url entries
            # For matugen, we need the SECOND download_url (source tarball), not the first (binary)
            if [[ "$PACKAGE" == "matugen" ]]; then
                # Find the second download_url service block (source tarball)
                # Skip first 5 lines to get to the second service block  
                SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "distro/debian/$PACKAGE/_service" | tail -n +5 | head -4)
                # Extract URL by removing XML tags
                SOURCE_URL=$(echo "$SERVICE_BLOCK" | grep 'url' | sed 's/^[[:space:]]*//; s/[^>]*>//; s/<.*//')
            else
                # Find the first download_url service block
                SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "distro/debian/$PACKAGE/_service" | head -10)
                
                URL_PROTOCOL=$(echo "$SERVICE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
                URL_HOST=$(echo "$SERVICE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
                URL_PATH=$(echo "$SERVICE_BLOCK" | grep "path" | sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/' | head -1)
                
                if [[ -n "$URL_PROTOCOL" &&-n "$URL_HOST" && -n "$URL_PATH" ]]; then
                    SOURCE_URL="${URL_PROTOCOL}://${URL_HOST}${URL_PATH}"
                fi
            fi
            
            # This block was duplicated and should be outside the if/else for matugen,
            # and only execute if SOURCE_URL was successfully determined.
            if [[ -n "$SOURCE_URL" ]]; then
                echo "    Downloading source from: $SOURCE_URL"
                
                # Special handling for niri: vendored-dependencies tarball needs git source
                if [[ "$PACKAGE" == "niri" && "$URL_PATH" == *"vendored-dependencies"* ]]; then
                    echo "    niri requires git source + vendored dependencies"
                    # Clone niri from git at the release tag
                    GIT_TAG=$(echo "$URL_PATH" | sed 's/.*\/v\([^/]*\)\/.*/\1/')
                    GIT_REPO="https://github.com/YaLTeR/niri.git"
                    SOURCE_DIR="$TEMP_DIR/niri"
                    echo "    Cloning niri from git (tag: $GIT_TAG)"
                    if git clone --depth 1 --branch "v$GIT_TAG" "$GIT_REPO" "$SOURCE_DIR" 2>/dev/null || \
                       git clone --depth 1 --branch "$GIT_TAG" "$GIT_REPO" "$SOURCE_DIR" 2>/dev/null; then
                        cd "$SOURCE_DIR"
                        git checkout "v$GIT_TAG" 2>/dev/null || git checkout "$GIT_TAG" 2>/dev/null || true
                        cd "$REPO_ROOT"
                    else
                        echo "Error: Failed to clone niri repository"
                        exit 1
                    fi
                    
                    # Download and extract vendored dependencies into the source directory
                    echo "    Downloading vendored dependencies"
                    if wget -q -O "$TEMP_DIR/vendor-archive" "$SOURCE_URL"; then
                        cd "$SOURCE_DIR"
                        if [[ "$SOURCE_URL" == *.tar.xz ]]; then
                            tar -xJf "$TEMP_DIR/vendor-archive"
                        elif [[ "$SOURCE_URL" == *.tar.gz ]]; then
                            tar -xzf "$TEMP_DIR/vendor-archive"
                        fi
                        # Verify smithay is in vendor directory
                        if [[ -d vendor ]] && ! find vendor -maxdepth 1 -type d -name "*smithay*" | grep -q .; then
                            echo "    Warning: smithay not found in vendor directory, checking structure"
                            ls -la vendor/ | head -10
                        fi
                        cd "$REPO_ROOT"
                    else
                        echo "Error: Failed to download vendored dependencies"
                        exit 1
                    fi
                    
                    # Create .cargo/config.toml to use existing vendored dependencies
                    echo "    Creating .cargo/config.toml for vendored dependencies"
                    cd "$SOURCE_DIR"
                    if [[ -d vendor ]]; then
                        mkdir -p .cargo
                        # Remove existing config to avoid duplicates
                        rm -f .cargo/config.toml
                        
                        if command -v cargo >/dev/null 2>&1; then
                            # Run cargo vendor to generate config (outputs to stderr)
                            # Use simple awk pattern like working Ubuntu builds - stops at directory line
                            cargo vendor --versioned-dirs 2>&1 | awk '
                                /^\[source\.crates-io\]/ { printing=1 }
                                printing { print }
                                /^directory = "vendor"$/ { exit }
                            ' > .cargo/config.toml
                            
                            # Verify config was created and has required sections
                            if [[ ! -s .cargo/config.toml ]] || ! grep -q "vendored-sources" .cargo/config.toml; then
                                echo "    Warning: cargo vendor config incomplete, creating clean config"
                                cat > .cargo/config.toml << 'CARGO_CONFIG_EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
CARGO_CONFIG_EOF
                            fi
                        else
                            # Fallback: create basic config
                            cat > .cargo/config.toml << 'CARGO_CONFIG_EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
CARGO_CONFIG_EOF
                        fi
                        echo "    Created .cargo/config.toml for vendored sources"
                    else
                        echo "Warning: vendor directory not found"
                    fi
                    cd "$REPO_ROOT"
                else
                    # Normal download and extract
                    if wget -q -O "$TEMP_DIR/source-archive" "$SOURCE_URL"; then
                        # Extract source (auto-detect compression)
                        cd "$TEMP_DIR"
                        if [[ "$SOURCE_URL" == *.tar.xz ]]; then
                            tar -xJf source-archive
                        elif [[ "$SOURCE_URL" == *.tar.gz ]] || [[ "$SOURCE_URL" == *.tgz ]]; then
                            tar -xzf source-archive
                        elif [[ "$SOURCE_URL" == *.tar.bz2 ]]; then
                            tar -xjf source-archive
                        else
                            # Try to auto-detect
                            tar -xf source-archive 2>/dev/null || {
                                echo "Error: Could not extract source archive"
                                exit 1
                            }
                        fi
                        cd "$REPO_ROOT"
                        
                        # Find extracted directory (usually first directory found, excluding temp dir itself)
                        SOURCE_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d ! -path "$TEMP_DIR" | head -1)
                    else
                        echo "Error: Failed to download source from $SOURCE_URL"
                        exit 1
                    fi
                fi
            fi
        elif grep -q "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service"; then
            # Extract git repository URL and revision
            GIT_URL=$(grep -A10 "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service" | grep "url" | sed 's/.*<param name="url">\(.*\)<\/param>.*/\1/' | head -1)
            GIT_REVISION=$(grep -A10 "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service" | grep "revision" | sed 's/.*<param name="revision">\(.*\)<\/param>.*/\1/' | head -1)
            
            if [[ -z "$GIT_REVISION" ]]; then
                GIT_REVISION="master"
            fi
            
            if [[ -n "$GIT_URL" ]]; then
                echo "    Cloning git repository: $GIT_URL (revision: $GIT_REVISION)"
                # Determine source directory name based on package
                if [[ "$PACKAGE" == "niri-git" ]]; then
                    SOURCE_DIR="$TEMP_DIR/niri"
                elif [[ "$PACKAGE" == "quickshell-git" ]]; then
                    # quickshell-git rules expect "quickshell-source" (without -git)
                    SOURCE_DIR="$TEMP_DIR/quickshell-source"
                else
                    SOURCE_DIR="$TEMP_DIR/$PACKAGE-source"
                fi
                if git clone --depth 1 --branch "$GIT_REVISION" "$GIT_URL" "$SOURCE_DIR" 2>/dev/null || \
                   git clone --depth 1 "$GIT_URL" "$SOURCE_DIR" 2>/dev/null; then
                    cd "$SOURCE_DIR"
                    git checkout "$GIT_REVISION" 2>/dev/null || true
                    # Ensure SOURCE_DIR is absolute after git operations
                    SOURCE_DIR=$(pwd)
                    cd "$REPO_ROOT"
                    
                    # For niri-git, run cargo vendor to create vendor directory
                    # For niri-git, run cargo vendor and save the config in the tarball
                    # The config is needed for offline builds with git dependencies
                    if [[ "$PACKAGE" == "niri-git" ]] && [[ -f "$SOURCE_DIR/Cargo.toml" ]]; then
                        echo "    Running cargo vendor for niri-git"
                        cd "$SOURCE_DIR"
                        if command -v cargo >/dev/null 2>&1; then
                            rm -rf vendor .cargo
                            # Run cargo vendor to create vendor directory with ALL dependencies including git
                            mkdir -p .cargo
                            cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || {
                                echo "Error: cargo vendor failed"
                                exit 1
                            }
                            
                            # Verify vendor was created and contains smithay (git dependency)
                            if [[ ! -d vendor ]]; then
                                echo "Error: cargo vendor failed to create vendor directory"
                                exit 1
                            fi
                            
                            # Verify config was created and includes git sources
                            if [[ ! -s .cargo/config.toml ]]; then
                                echo "Error: cargo vendor failed to generate config"
                                exit 1
                            fi
                            
                            # Check if smithay is in vendor (it's a git dependency)
                            if ! find vendor -maxdepth 1 -type d -name "*smithay*" | grep -q .; then
                                echo "Warning: smithay not found in vendor directory"
                                echo "Vendor directory contents:"
                                ls -la vendor/ | head -20
                            fi
                            
                            # Verify config includes git source mappings
                            if ! grep -q "github.com/Smithay/smithay" .cargo/config.toml 2>/dev/null; then
                                echo "Warning: smithay git source not found in config"
                                echo "Config contents:"
                                cat .cargo/config.toml
                            fi
                            
                            echo "    Created vendor directory and .cargo/config.toml (included in tarball)"
                        else
                            echo "Warning: cargo not available for niri-git"
                        fi
                        cd "$REPO_ROOT"
                    fi
                else
                    echo "Error: Failed to clone git repository"
                    exit 1
                fi
            fi
        fi
    fi
    
    # If no source directory found, error out (except for special packages like matugen)
    if [[ "$PACKAGE" != "matugen" ]] && [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
        echo "Error: Could not determine or obtain source for $PACKAGE"
        echo "       Please ensure _service file is properly configured or source is available"
        exit 1
    fi
    
    # Ensure SOURCE_DIR is an absolute path (skip for matugen)
    if [[ "$PACKAGE" != "matugen" ]] && [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]]; then
        SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
        echo "    Source directory (absolute): $SOURCE_DIR"
    fi
    
    # Special handling for Go packages that need vendor directory
    if [[ "$PACKAGE" == "cliphist" ]] && [[ -f "$SOURCE_DIR/go.mod" ]] && [[ ! -d "$SOURCE_DIR/vendor" ]]; then
        echo "    Generating Go vendor directory for cliphist"
        cd "$SOURCE_DIR"
        if command -v go >/dev/null 2>&1; then
            go mod vendor || {
                echo "Warning: Failed to generate vendor directory, build may fail"
            }
        else
            echo "Warning: Go not available, vendor directory not generated"
        fi
        cd "$REPO_ROOT"
    fi
    
    
    # Create OpenSUSE-compatible source tarballs BEFORE adding debian/ directory
    # (OpenSUSE doesn't need debian/ directory)
    # Save original SOURCE_DIR before any modifications (skip for matugen which handles sources differently)
    if [[ "$PACKAGE" != "matugen" ]]; then
        ORIGINAL_SOURCE_DIR="$SOURCE_DIR"
    fi
    
    # Check if we should skip openSUSE for this package
    # niri stable is Debian-only (openSUSE only builds niri-git)
    SKIP_OPENSUSE=false
    if [[ "$PACKAGE" == "niri" && "$UPLOAD_OPENSUSE" == true ]]; then
        echo "  - Note: niri stable is Debian-only (openSUSE builds niri-git)"
        SKIP_OPENSUSE=true
        UPLOAD_OPENSUSE=false
    fi
    
    if [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
        echo "  - Creating OpenSUSE-compatible source tarballs"
        
        # Extract Source0 from spec file
        SOURCE0=$(grep "^Source0:" "distro/opensuse/$PACKAGE.spec" | sed 's/^Source0:[[:space:]]*//' | head -1)
        
        if [[ -n "$SOURCE0" ]]; then
            # Create a separate subdirectory for OpenSUSE tarball creation to avoid conflicts
            # with the original source directory
            OBS_TARBALL_DIR="$TEMP_DIR/.obs-tarball-work-$$"
            mkdir -p "$OBS_TARBALL_DIR"
            cd "$OBS_TARBALL_DIR"
            # Always use absolute path to original source directory for copying
            # This ensures we never accidentally remove the original
            ORIGINAL_BASENAME=$(basename "$ORIGINAL_SOURCE_DIR")
            
            case "$PACKAGE" in
                niri)
                    # niri spec expects niri.tar.xz with directory named "niri-v0.1.10" (from %setup -q -n niri-v%{version})
                    # Extract version from spec file
                    NIRI_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                    EXPECTED_DIR="niri-v${NIRI_VERSION}"
                    TARBALL_WORK=".${EXPECTED_DIR}-work-$$"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    # Always copy from absolute path to ensure we don't touch the original
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    # Always rename to expected name (safe since TARBALL_WORK is unique)
                    mv "$TARBALL_WORK" "$EXPECTED_DIR"
                    tar -cJf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                niri-git)
                    # niri-git spec expects niri.tar (uncompressed) with directory named "niri"
                    echo "    Creating $SOURCE0 (directory: niri)"
                    # Use a unique temp name that won't conflict with original
                    TARBALL_WORK=".niri-tarball-work-$$"
                    # Always copy from absolute path to ensure we don't touch the original
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    # Always rename to expected name (safe since TARBALL_WORK is unique)
                    mv "$TARBALL_WORK" "niri"
                    tar -cf "$WORK_DIR/$SOURCE0" "niri"
                    rm -rf "niri"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                cliphist)
                    # cliphist spec expects cliphist.tar.gz with directory named "cliphist-0.7.0" (from %setup -q -n cliphist-0.7.0)
                    # Extract version from spec file
                    CLIPHIST_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                    EXPECTED_DIR="cliphist-${CLIPHIST_VERSION}"
                    TARBALL_WORK=".${EXPECTED_DIR}-work-$$"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    # Always copy from absolute path to ensure we don't touch the original
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    # Always rename to expected name (safe since TARBALL_WORK is unique)
                    mv "$TARBALL_WORK" "$EXPECTED_DIR"
                    tar -czf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                quickshell-git)
                    # quickshell-git spec expects quickshell-source.tar.gz with directory "quickshell-source"
                    echo "    Creating $SOURCE0 (directory: quickshell-source)"
                    TARBALL_WORK=".quickshell-source-work-$$"
                    # Always copy from absolute path to ensure we don't touch the original
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    # Always rename to expected name (safe since TARBALL_WORK is unique)
                    mv "$TARBALL_WORK" quickshell-source
                    tar -czf "$WORK_DIR/$SOURCE0" quickshell-source
                    rm -rf quickshell-source
                    ;;
                matugen)
                    # matugen spec has two sources:
                    # Source0: matugen-amd64.tar.gz (binary for x86_64)
                    # Source1: matugen-source.tar.gz (source for other architectures)
                    # We need to download both from the _service file URLs
                    echo "    Creating matugen tarballs from _service URLs"
                    
                    # Download Source0 (binary) - first download_url
                    BINARY_URL=$(awk '/<service name="download_url">/,/<\/service>/' "$REPO_ROOT/distro/debian/$PACKAGE/_service" | head -4 | grep 'param name="url"' | sed 's/.*<param name="url">\(.*\)<\/param>/\1/')
                    echo "    Downloading binary from: $BINARY_URL"
                    wget -q -O "$WORK_DIR/$SOURCE0" "$BINARY_URL" || {
                        echo "    Error: Failed to download binary tarball"
                        exit 1
                    }
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    
                    # Download Source1 (source) - second download_url
                    SOURCE1=$(grep "^Source1:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Source1:[[:space:]]*//' | head -1)
                    if [[ -n "$SOURCE1" ]]; then
                        SOURCE_TARBALL_URL=$(awk '/<service name="download_url">/,/<\/service>/' "$REPO_ROOT/distro/debian/$PACKAGE/_service" | tail -n +5 | head -4 | grep 'param name="url"' | sed 's/.*<param name="url">\(.*\)<\/param>/\1/')
                        echo "    Downloading source from: $SOURCE_TARBALL_URL"
                        wget -q -O "$WORK_DIR/$SOURCE1" "$SOURCE_TARBALL_URL" || {
                            echo "    Error: Failed to download source tarball"
                            exit 1
                        }
                        echo "    Created $SOURCE1 ($(stat -c%s "$WORK_DIR/$SOURCE1" 2>/dev/null || echo 0) bytes)"
                    fi
                    ;;
                *)
                    # Generic handling
                    echo "    Creating $SOURCE0 (directory: $ORIGINAL_BASENAME)"
                    # Always copy from absolute path to ensure we don't touch the original
                    TARBALL_WORK=".${ORIGINAL_BASENAME}-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    if [[ "$SOURCE0" == *.tar.xz ]]; then
                        tar -cJf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    elif [[ "$SOURCE0" == *.tar.bz2 ]]; then
                        tar -cjf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    else
                        tar -czf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    fi
                    # Only remove the copy we created (always safe since it's a unique work name)
                    rm -rf "$TARBALL_WORK"
                    ;;
            esac
            # Clean up the tarball work directory
            cd "$REPO_ROOT"
            rm -rf "$OBS_TARBALL_DIR"
            echo "  - OpenSUSE source tarballs created"
        fi
        
        # Copy spec file
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"

        # Auto-increment Release if same Version is being rebuilt
        if [[ -f "$WORK_DIR/.osc/$PACKAGE.spec" ]]; then
            # Get Version and Release from new spec
            NEW_VERSION=$(grep "^Version:" "$WORK_DIR/$PACKAGE.spec" | awk '{print $2}' | head -1)
            NEW_RELEASE=$(grep "^Release:" "$WORK_DIR/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            # Get Version and Release from existing spec in OBS
            OLD_VERSION=$(grep "^Version:" "$WORK_DIR/.osc/$PACKAGE.spec" | awk '{print $2}' | head -1)
            OLD_RELEASE=$(grep "^Release:" "$WORK_DIR/.osc/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
                # Same version - increment release number
                # Extract numeric part (e.g., "1" from "1" or "12" from "12.1")
                if [[ "$OLD_RELEASE" =~ ^([0-9]+) ]]; then
                    BASE_RELEASE="${BASH_REMATCH[1]}"
                    NEXT_RELEASE=$((BASE_RELEASE + 1))
                    echo "  - Detected rebuild of same version $NEW_VERSION (release $OLD_RELEASE -> $NEXT_RELEASE)"
                    # Update Release in spec
                    sed -i "s/^Release:[[:space:]]*${NEW_RELEASE}%{?dist}/Release:        ${NEXT_RELEASE}%{?dist}/" "$WORK_DIR/$PACKAGE.spec"
                fi
            else
                echo "  - New version detected: $OLD_VERSION -> $NEW_VERSION (keeping release $NEW_RELEASE)"
            fi
        else
            echo "  - First upload to OBS (no previous spec found)"
        fi
    elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
        echo "  - Warning: OpenSUSE spec file not found, skipping OpenSUSE upload"
    fi
    
    # Restore original SOURCE_DIR (in case it was modified during OpenSUSE tarball creation)
    # Skip for matugen which doesn't use SOURCE_DIR
    if [[ "$PACKAGE" != "matugen" ]]; then
        SOURCE_DIR="$ORIGINAL_SOURCE_DIR"
        
        # Verify SOURCE_DIR still exists after OpenSUSE tarball creation
        if [[ ! -d "$SOURCE_DIR" ]]; then
            echo "Error: Source directory was removed or doesn't exist: $SOURCE_DIR"
            echo "  Temp directory contents:"
            ls -la "$TEMP_DIR" 2>/dev/null | head -10
            exit 1
        fi
    fi
    
    # Copy debian/ directory into source (for Debian builds only)
    if [[ "$UPLOAD_DEBIAN" == true ]] && [[ -d "distro/debian/$PACKAGE/debian" ]]; then
        echo "    Adding debian/ directory to source"
        echo "    Source directory: $SOURCE_DIR"
        echo "    Copying from: distro/debian/$PACKAGE/debian"
        
        # Verify source directory exists and is accessible
        if [[ ! -d "$SOURCE_DIR" ]]; then
            echo "Error: Source directory does not exist: $SOURCE_DIR"
            echo "  Checking if it's a file instead:"
            ls -la "$SOURCE_DIR" 2>/dev/null || echo "  Path does not exist at all"
            exit 1
        fi
        
        # Copy debian directory
        cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/" || {
            echo "Error: Failed to copy debian/ directory"
            exit 1
        }
        
        # Ensure debian/source/format exists if source/format file exists
        if [[ -f "distro/debian/$PACKAGE/debian/source/format" ]]; then
            mkdir -p "$SOURCE_DIR/debian/source"
            cp "distro/debian/$PACKAGE/debian/source/format" "$SOURCE_DIR/debian/source/format"
        fi
        
        # Verify debian/changelog exists
        if [[ ! -f "$SOURCE_DIR/debian/changelog" ]]; then
            echo "Error: debian/changelog not found after copying debian/ directory"
            echo "  Expected at: $SOURCE_DIR/debian/changelog"
            echo "  Source directory contents:"
            ls -la "$SOURCE_DIR/" 2>/dev/null | head -10
            echo "  Debian directory contents:"
            ls -la "$SOURCE_DIR/debian/" 2>/dev/null | head -10
            exit 1
        fi
        echo "    Verified debian/changelog exists"
        
        # Create combined tarball for Debian (with debian/ directory)
        cd "$TEMP_DIR"
        # Get the directory name inside (should be the source directory name)
        DIR_NAME=$(basename "$SOURCE_DIR")
        tar -czf "$WORK_DIR/$COMBINED_TARBALL" "$DIR_NAME"
        cd "$REPO_ROOT"
        
        # Calculate MD5 and size for .dsc file
        TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)
        TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL")
        
        echo "    Created: $COMBINED_TARBALL (MD5: $TARBALL_MD5, Size: $TARBALL_SIZE bytes)"
        
        # Extract Build-Depends from control file
        BUILD_DEPS="debhelper-compat (= 13)"
        if [[ -f "distro/debian/$PACKAGE/debian/control" ]]; then
            # Extract Build-Depends field (handles multi-line with proper continuation)
            # Use sed to extract from Build-Depends: to next field (line starting with capital letter)
            CONTROL_DEPS=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "distro/debian/$PACKAGE/debian/control" | \
                sed '/^Build-Depends:/s/^Build-Depends: *//' | \
                sed '/^[A-Z]/d' | \
                tr '\n' ' ' | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
            if [[ -n "$CONTROL_DEPS" && "$CONTROL_DEPS" != "" ]]; then
                BUILD_DEPS="$CONTROL_DEPS"
            fi
        fi
        
        # Generate .dsc file for native format
        cat > "$WORK_DIR/$PACKAGE.dsc" << EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $CHANGELOG_VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: $BUILD_DEPS
DEBTRANSFORM-TAR: $COMBINED_TARBALL
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF
        
        # Don't copy _service file for native format - we've already created the combined tarball
        echo "  - Native format: using combined tarball (no _service file needed)"
    elif [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "Error: debian/ directory not found for $PACKAGE"
        exit 1
    fi
else
    # Quilt format - use separate debian.tar.gz
    if [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "  - Using quilt format (separate debian.tar.gz)"
        
        # Create debian.tar.gz if debian/ exists
        if [[ -d "distro/debian/$PACKAGE/debian" ]]; then
            echo "  - Creating debian.tar.gz"
            tar -czf "$WORK_DIR/debian.tar.gz" -C "distro/debian/$PACKAGE" debian/
        fi
        
        # Copy _service file
        if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
            echo "  - Copying _service"
            cp "distro/debian/$PACKAGE/_service" "$WORK_DIR/"
        fi
        
        # Extract Build-Depends from control file
        BUILD_DEPS="debhelper-compat (= 13)"
        if [[ -f "distro/debian/$PACKAGE/debian/control" ]]; then
            # Extract Build-Depends field (handles multi-line with proper continuation)
            # Use sed to extract from Build-Depends: to next field (line starting with capital letter)
            CONTROL_DEPS=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "distro/debian/$PACKAGE/debian/control" | \
                sed '/^Build-Depends:/s/^Build-Depends: *//' | \
                sed '/^[A-Z]/d' | \
                tr '\n' ' ' | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
            if [[ -n "$CONTROL_DEPS" && "$CONTROL_DEPS" != "" ]]; then
                BUILD_DEPS="$CONTROL_DEPS"
            fi
        fi
        
        # Generate .dsc file for quilt format
        cat > "$WORK_DIR/$PACKAGE.dsc" << EOF
Format: 3.0 (quilt)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $CHANGELOG_VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: $BUILD_DEPS
DEBTRANSFORM-TAR: debian.tar.gz
Files:
 00000000000000000000000000000000 1 debian.tar.gz
EOF
    fi
    
    # For quilt format, also create OpenSUSE tarballs if spec exists
    # (For native format, OpenSUSE tarballs are created above before adding debian/)
    if [[ "$UPLOAD_OPENSUSE" == true ]] && [[ "$SOURCE_FORMAT" != *"native"* ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
        echo "  - Note: OpenSUSE tarballs for quilt format should be handled via _service file"
        echo "  - Copying $PACKAGE.spec for OpenSUSE"
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"

        # Auto-increment Release if same Version is being rebuilt
        if [[ -f "$WORK_DIR/.osc/$PACKAGE.spec" ]]; then
            # Get Version and Release from new spec
            NEW_VERSION=$(grep "^Version:" "$WORK_DIR/$PACKAGE.spec" | awk '{print $2}' | head -1)
            NEW_RELEASE=$(grep "^Release:" "$WORK_DIR/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            # Get Version and Release from existing spec in OBS
            OLD_VERSION=$(grep "^Version:" "$WORK_DIR/.osc/$PACKAGE.spec" | awk '{print $2}' | head -1)
            OLD_RELEASE=$(grep "^Release:" "$WORK_DIR/.osc/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
                # Same version - increment release number
                # Extract numeric part (e.g., "1" from "1" or "12" from "12.1")
                if [[ "$OLD_RELEASE" =~ ^([0-9]+) ]]; then
                    BASE_RELEASE="${BASH_REMATCH[1]}"
                    NEXT_RELEASE=$((BASE_RELEASE + 1))
                    echo "  - Detected rebuild of same version $NEW_VERSION (release $OLD_RELEASE -> $NEXT_RELEASE)"
                    # Update Release in spec
                    sed -i "s/^Release:[[:space:]]*${NEW_RELEASE}%{?dist}/Release:        ${NEXT_RELEASE}%{?dist}/" "$WORK_DIR/$PACKAGE.spec"
                fi
            else
                echo "  - New version detected: $OLD_VERSION -> $NEW_VERSION (keeping release $NEW_RELEASE)"
            fi
        else
            echo "  - First upload to OBS (no previous spec found)"
        fi
    fi
fi

# Change to working directory and commit
cd "$WORK_DIR"

echo "==> Staging changes"
# List files to be uploaded
echo "Files to upload:"
if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh *.tar.gz *.tar.xz *.tar *.spec *.dsc _service 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    ls -lh *.tar.gz *.dsc _service 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh *.tar.gz *.tar.xz *.tar *.spec 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
fi
echo ""

osc addremove

echo "==> Committing to OBS"
echo "  (This may take several minutes for large files...)"
# Use timeout to prevent indefinite hanging, but allow enough time for large uploads
# 30 minutes should be enough for ~1GB uploads on slow connections
timeout 1800 osc commit -m "$MESSAGE" || {
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 124 ]]; then
        echo "Error: Upload timed out after 30 minutes"
        echo "  Large files may need more time. Try uploading manually:"
        echo "  cd $WORK_DIR && osc commit -m \"$MESSAGE\""
        exit 1
    else
        echo "Error: Upload failed with exit code $EXIT_CODE"
        exit 1
    fi
}

echo "==> Checking build status"
osc results

echo ""
echo "Upload complete! Monitor builds with:"
echo "  cd $WORK_DIR && osc results"
echo "  cd $WORK_DIR && osc buildlog REPO ARCH"
echo ""

# Don't cleanup - keep checkout for status checking
echo ""
echo "Upload complete! Build status:"
cd "$WORK_DIR"
osc results 2>&1 | head -10
cd "$REPO_ROOT"

echo ""
echo "To check detailed status:"
echo "  cd $WORK_DIR && osc results"
echo "  cd $WORK_DIR && osc remotebuildlog $OBS_PROJECT $PACKAGE Debian_13 x86_64"
echo ""
echo "NOTE: Checkout kept at $WORK_DIR for status checking"
echo ""
echo "✅ Upload complete!"
echo ""
echo "Check build status with:"
echo "  ./distro/scripts/obs-status.sh $PACKAGE"
