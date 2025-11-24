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

# Download all files from _service download_url entries into a directory
download_service_files() {
    local service_file="$1"
    local target_dir="$2"
    
    # Extract all url/filename pairs from download_url services
    local urls=$(grep -A2 '<service name="download_url">' "$service_file" | grep 'param name="url"' | sed 's/.*<param name="url">\(.*\)<\/param>.*/\1/')
    local filenames=$(grep -A2 '<service name="download_url">' "$service_file" | grep 'param name="filename"' | sed 's/.*<param name="filename">\(.*\)<\/param>.*/\1/')
    
    local url_arr=($urls)
    local file_arr=($filenames)
    
    for i in "${!url_arr[@]}"; do
        local url="${url_arr[$i]}"
        local filename="${file_arr[$i]:-$(basename "$url")}"
        echo "    Downloading: $filename"
        if curl -L -f -s -o "$target_dir/$filename" "$url" 2>/dev/null || \
           wget -q -O "$target_dir/$filename" "$url" 2>/dev/null; then
            :
        else
            echo "Error: Failed to download $url"
            return 1
        fi
    done
    return 0
}

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
fi

if [[ -z "$MESSAGE" ]]; then
    MESSAGE="Update packaging"
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "distro/debian" ]]; then
    echo "Error: Run this script from the repository root"
    exit 1
fi

# Handle "all" option
if [[ "$PACKAGE" == "all" ]]; then
    echo "==> Uploading all packages"
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

OBS_PROJECT="${OBS_BASE_PROJECT}:${PROJECT}"

echo "==> Target: $OBS_PROJECT / $PACKAGE"
if [[ "$UPLOAD_DEBIAN" == true && "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distributions: Debian + OpenSUSE"
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    echo "==> Distribution: Debian only"
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Distribution: OpenSUSE only"
fi

mkdir -p "$OBS_BASE"

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

find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.bz2" -o -name "*.tar" -o -name "*.spec" -o -name "_service" -o -name "*.dsc" \) -delete 2>/dev/null || true

CHANGELOG_VERSION=$(grep -m1 "^$PACKAGE" distro/debian/$PACKAGE/debian/changelog 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "0.1.11-1")
SOURCE_FORMAT=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")

# Native format cannot have Debian revisions, strip them if present
if [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
    CHANGELOG_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/-[0-9]*$//')
    echo "  Warning: Removed Debian revision from version for native format: $CHANGELOG_VERSION"
fi


# Format 3.0 (native) requires: <package>_<version>.tar.gz
if [[ "$SOURCE_FORMAT" == *"native"* ]]; then
    COMBINED_TARBALL="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
    echo "  - Creating combined source tarball for native format: $COMBINED_TARBALL"
    
    SOURCE_DIR=""
    
    if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
        if grep -q "download_url" "distro/debian/$PACKAGE/_service"; then
            # For matugen, skip SOURCE_DIR creation - it uses pre-downloaded tarballs
            if [[ "$PACKAGE" == "matugen" ]]; then
                echo "    matugen uses pre-downloaded tarballs, skipping source extraction"
                SOURCE_DIR=""
            else
                SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "distro/debian/$PACKAGE/_service" | head -10)
                URL_PROTOCOL=$(echo "$SERVICE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
                URL_HOST=$(echo "$SERVICE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
                URL_PATH=$(echo "$SERVICE_BLOCK" | grep "path" | sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/' | head -1)
                
                if [[ -n "$URL_PROTOCOL" &&-n "$URL_HOST" && -n "$URL_PATH" ]]; then
                    SOURCE_URL="${URL_PROTOCOL}://${URL_HOST}${URL_PATH}"
                fi
            fi
            
            if [[ -n "$SOURCE_URL" ]]; then
                echo "    Downloading source from: $SOURCE_URL"
                
                # Special handling for niri: vendored-dependencies tarball needs git source
                if [[ "$PACKAGE" == "niri" && "$URL_PATH" == *"vendored-dependencies"* ]]; then
                    echo "    niri requires git source + vendored dependencies"
                    GIT_TAG=$(echo "$URL_PATH" | sed 's/.*\/v\([^/]*\)\/.*/\1/')
                    GIT_REPO="https://github.com/YaLTeR/niri.git"
                    SOURCE_DIR="$TEMP_DIR/niri"
                    echo "    Cloning niri from git (tag: $GIT_TAG)"
                    if git clone --depth 1 --branch "v$GIT_TAG" "$GIT_REPO" "$SOURCE_DIR" 2>/dev/null || \
                       git clone --depth 1 --branch "$GIT_TAG" "$GIT_REPO" "$SOURCE_DIR" 2>/dev/null; then
                        cd "$SOURCE_DIR"
                        git checkout "v$GIT_TAG" 2>/dev/null || git checkout "$GIT_TAG" 2>/dev/null || true
                        rm -rf .git
                        cd "$REPO_ROOT"
                    else
                        echo "Error: Failed to clone niri repository"
                        exit 1
                    fi
                    
                    echo "    Downloading vendored dependencies"
                    if curl -L -f -s -o "$TEMP_DIR/vendor-archive" "$SOURCE_URL" 2>/dev/null || \
                       wget -q -O "$TEMP_DIR/vendor-archive" "$SOURCE_URL" 2>/dev/null; then
                        cd "$SOURCE_DIR"
                        if [[ "$SOURCE_URL" == *.tar.xz ]]; then
                            tar -xJf "$TEMP_DIR/vendor-archive"
                        elif [[ "$SOURCE_URL" == *.tar.gz ]]; then
                            tar -xzf "$TEMP_DIR/vendor-archive"
                        fi
                        if [[ -d vendor ]] && ! find vendor -maxdepth 1 -type d -name "*smithay*" | grep -q .; then
                            echo "    Warning: smithay not found in vendor directory, checking structure"
                            ls -la vendor/ | head -10
                        fi
                        cd "$REPO_ROOT"
                    else
                        echo "Error: Failed to download vendored dependencies"
                        exit 1
                    fi
                    
                    echo "    Creating .cargo/config.toml for vendored dependencies"
                    cd "$SOURCE_DIR"
                    if [[ -d vendor ]]; then
                        mkdir -p .cargo
                        rm -f .cargo/config.toml
                        
                        if command -v cargo >/dev/null 2>&1; then
                            cargo vendor --versioned-dirs 2>&1 | awk '
                                /^\[source\.crates-io\]/ { printing=1 }
                                printing { print }
                                /^directory = "vendor"$/ { exit }
                            ' > .cargo/config.toml
                            
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
                    if curl -L -f -s -o "$TEMP_DIR/source-archive" "$SOURCE_URL" 2>/dev/null || \
                       wget -q -O "$TEMP_DIR/source-archive" "$SOURCE_URL" 2>/dev/null; then
                        cd "$TEMP_DIR"
                        if [[ "$SOURCE_URL" == *.tar.xz ]]; then
                            tar -xJf source-archive
                        elif [[ "$SOURCE_URL" == *.tar.gz ]] || [[ "$SOURCE_URL" == *.tgz ]]; then
                            tar -xzf source-archive
                        elif [[ "$SOURCE_URL" == *.tar.bz2 ]]; then
                            tar -xjf source-archive
                        else
                            tar -xf source-archive 2>/dev/null || {
                                echo "Error: Could not extract source archive"
                                exit 1
                            }
                        fi
                        cd "$REPO_ROOT"
                        SOURCE_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d ! -path "$TEMP_DIR" | head -1)
                    else
                        echo "Error: Failed to download source from $SOURCE_URL"
                        exit 1
                    fi
                fi
            fi
        elif grep -q "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service"; then
            GIT_URL=$(grep -A10 "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service" | grep "url" | sed 's/.*<param name="url">\(.*\)<\/param>.*/\1/' | head -1)
            GIT_REVISION=$(grep -A10 "tar_scm\|obs_scm" "distro/debian/$PACKAGE/_service" | grep "revision" | sed 's/.*<param name="revision">\(.*\)<\/param>.*/\1/' | head -1)
            
            if [[ -z "$GIT_REVISION" ]]; then
                GIT_REVISION="master"
            fi
            
            if [[ -n "$GIT_URL" ]]; then
                echo "    Cloning git repository: $GIT_URL (revision: $GIT_REVISION)"
                if [[ "$PACKAGE" == "niri-git" ]]; then
                    SOURCE_DIR="$TEMP_DIR/niri"
                elif [[ "$PACKAGE" == "quickshell-git" ]]; then
                    SOURCE_DIR="$TEMP_DIR/quickshell-source"
                else
                    SOURCE_DIR="$TEMP_DIR/$PACKAGE-source"
                fi
                if git clone --depth 1 --branch "$GIT_REVISION" "$GIT_URL" "$SOURCE_DIR" 2>/dev/null || \
                   git clone --depth 1 "$GIT_URL" "$SOURCE_DIR" 2>/dev/null; then
                    cd "$SOURCE_DIR"
                    git checkout "$GIT_REVISION" 2>/dev/null || true
                    rm -rf .git
                    SOURCE_DIR=$(pwd)
                    cd "$REPO_ROOT"
                    
                    # For niri-git, run cargo vendor to create vendor directory
                    # The config is needed for offline builds with git dependencies
                    if [[ "$PACKAGE" == "niri-git" ]] && [[ -f "$SOURCE_DIR/Cargo.toml" ]]; then
                        echo "    Running cargo vendor for niri-git"
                        cd "$SOURCE_DIR"
                        if command -v cargo >/dev/null 2>&1; then
                            rm -rf vendor .cargo
                            mkdir -p .cargo
                            cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || {
                                echo "Error: cargo vendor failed"
                                exit 1
                            }
                            
                            if [[ ! -d vendor ]]; then
                                echo "Error: cargo vendor failed to create vendor directory"
                                exit 1
                            fi
                            
                            if [[ ! -s .cargo/config.toml ]]; then
                                echo "Error: cargo vendor failed to generate config"
                                exit 1
                            fi
                            
                            if ! find vendor -maxdepth 1 -type d -name "*smithay*" | grep -q .; then
                                echo "Warning: smithay not found in vendor directory"
                                echo "Vendor directory contents:"
                                ls -la vendor/ | head -20
                            fi
                            
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
    
    if [[ "$PACKAGE" != "matugen" ]] && [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
        echo "Error: Could not determine or obtain source for $PACKAGE"
        echo "       Please ensure _service file is properly configured or source is available"
        exit 1
    fi
    
    if [[ "$PACKAGE" != "matugen" ]] && [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR" ]]; then
        SOURCE_DIR=$(cd "$SOURCE_DIR" && pwd)
        echo "    Source directory (absolute): $SOURCE_DIR"
    fi
    
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
    if [[ "$PACKAGE" != "matugen" ]]; then
        ORIGINAL_SOURCE_DIR="$SOURCE_DIR"
    fi
    
    # niri stable is Debian-only (openSUSE only builds niri-git)
    if [[ "$PACKAGE" == "niri" && "$UPLOAD_OPENSUSE" == true ]]; then
        echo "  - Note: niri stable is Debian-only (openSUSE builds niri-git)"
        UPLOAD_OPENSUSE=false
    fi
    
    if [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
        echo "  - Creating OpenSUSE-compatible source tarballs"
        
        SOURCE0=$(grep "^Source0:" "distro/opensuse/$PACKAGE.spec" | sed 's/^Source0:[[:space:]]*//' | head -1)
        
        if [[ -n "$SOURCE0" ]]; then
            OBS_TARBALL_DIR="$TEMP_DIR/.obs-tarball-work-$$"
            mkdir -p "$OBS_TARBALL_DIR"
            cd "$OBS_TARBALL_DIR"
            ORIGINAL_BASENAME=$(basename "$ORIGINAL_SOURCE_DIR")
            
            case "$PACKAGE" in
                niri)
                    NIRI_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                    EXPECTED_DIR="niri-v${NIRI_VERSION}"
                    TARBALL_WORK=".${EXPECTED_DIR}-work-$$"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" "$EXPECTED_DIR"
                    tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cJf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                niri-git)
                    echo "    Creating $SOURCE0 (directory: niri)"
                    TARBALL_WORK=".niri-tarball-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" "niri"
                    tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cf "$WORK_DIR/$SOURCE0" "niri"
                    rm -rf "niri"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                cliphist)
                    CLIPHIST_VERSION=$(grep "^Version:" "$REPO_ROOT/distro/opensuse/$PACKAGE.spec" | sed 's/^Version:[[:space:]]*//' | head -1)
                    EXPECTED_DIR="cliphist-${CLIPHIST_VERSION}"
                    TARBALL_WORK=".${EXPECTED_DIR}-work-$$"
                    echo "    Creating $SOURCE0 (directory: $EXPECTED_DIR)"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" "$EXPECTED_DIR"
                    tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$SOURCE0" "$EXPECTED_DIR"
                    rm -rf "$EXPECTED_DIR"
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                quickshell-git)
                    echo "    Creating $SOURCE0 (directory: quickshell-source)"
                    TARBALL_WORK=".quickshell-source-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" quickshell-source
                    tar --sort=name --mtime='2000-01-01 00:00:00' -czf "$WORK_DIR/$SOURCE0" quickshell-source
                    rm -rf quickshell-source
                    ;;
                matugen)
                    # matugen spec has two sources: Source0 (binary) and Source1 (source)
                    echo "    Creating matugen tarballs from _service URLs"
                    BINARY_URL=$(awk '/<service name="download_url">/,/<\/service>/' "$REPO_ROOT/distro/debian/$PACKAGE/_service" | head -4 | grep 'param name="url"' | sed 's/.*<param name="url">\(.*\)<\/param>/\1/')
                    echo "    Downloading binary from: $BINARY_URL"
                    wget -q -O "$WORK_DIR/$SOURCE0" "$BINARY_URL" || {
                        echo "    Error: Failed to download binary tarball"
                        exit 1
                    }
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    
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
                    echo "    Creating $SOURCE0 (directory: $ORIGINAL_BASENAME)"
                    TARBALL_WORK=".${ORIGINAL_BASENAME}-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    if [[ "$SOURCE0" == *.tar.xz ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cJf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    elif [[ "$SOURCE0" == *.tar.bz2 ]]; then
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -cjf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    else
                        tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$SOURCE0" "$TARBALL_WORK"
                    fi
                    rm -rf "$TARBALL_WORK"
                    ;;
            esac
            cd "$REPO_ROOT"
            rm -rf "$OBS_TARBALL_DIR"
            echo "  - OpenSUSE source tarballs created"
        fi
        
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"

        if [[ -f "$WORK_DIR/.osc/$PACKAGE.spec" ]]; then
            NEW_VERSION=$(grep "^Version:" "$WORK_DIR/$PACKAGE.spec" | awk '{print $2}' | head -1)
            NEW_RELEASE=$(grep "^Release:" "$WORK_DIR/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)
            OLD_VERSION=$(grep "^Version:" "$WORK_DIR/.osc/$PACKAGE.spec" | awk '{print $2}' | head -1)
            OLD_RELEASE=$(grep "^Release:" "$WORK_DIR/.osc/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            if [[ -n "${REBUILD_RELEASE:-}" ]]; then
                echo "  🔄 Using manual rebuild release number: $REBUILD_RELEASE"
                sed -i "s/^Release:[[:space:]]*${NEW_RELEASE}%{?dist}/Release:        ${REBUILD_RELEASE}%{?dist}/" "$WORK_DIR/$PACKAGE.spec"
            elif [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
                if [[ "$OLD_RELEASE" =~ ^([0-9]+) ]]; then
                    BASE_RELEASE="${BASH_REMATCH[1]}"
                    NEXT_RELEASE=$((BASE_RELEASE + 1))
                    echo "  - Detected rebuild of same version $NEW_VERSION (release $OLD_RELEASE -> $NEXT_RELEASE)"
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
    
    if [[ "$PACKAGE" != "matugen" ]]; then
        SOURCE_DIR="$ORIGINAL_SOURCE_DIR"
        
        if [[ ! -d "$SOURCE_DIR" ]]; then
            echo "Error: Source directory was removed or doesn't exist: $SOURCE_DIR"
            echo "  Temp directory contents:"
            ls -la "$TEMP_DIR" 2>/dev/null | head -10
            exit 1
        fi
    fi
    
    if [[ "$UPLOAD_DEBIAN" == true ]] && [[ -d "distro/debian/$PACKAGE/debian" ]]; then
        if [[ "$PACKAGE" == "matugen" ]]; then
            echo "    Creating matugen combined tarball"
            PKG_DIR="$TEMP_DIR/matugen-package"
            mkdir -p "$PKG_DIR"
            download_service_files "distro/debian/$PACKAGE/_service" "$PKG_DIR" || exit 1
            cp -r "distro/debian/$PACKAGE/debian" "$PKG_DIR/"
            cd "$TEMP_DIR"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "matugen-package"
            cd "$REPO_ROOT"
        else
            echo "    Adding debian/ directory to source"
            
            if [[ ! -d "$SOURCE_DIR" ]]; then
                echo "Error: Source directory does not exist: $SOURCE_DIR"
                ls -la "$SOURCE_DIR" 2>/dev/null || echo "  Path does not exist at all"
                exit 1
            fi
            
            cp -r "distro/debian/$PACKAGE/debian" "$SOURCE_DIR/" || {
                echo "Error: Failed to copy debian/ directory"
                exit 1
            }
            
            if [[ -f "distro/debian/$PACKAGE/debian/source/format" ]]; then
                mkdir -p "$SOURCE_DIR/debian/source"
                cp "distro/debian/$PACKAGE/debian/source/format" "$SOURCE_DIR/debian/source/format"
            fi
            
            if [[ ! -f "$SOURCE_DIR/debian/changelog" ]]; then
                echo "Error: debian/changelog not found after copying debian/ directory"
                echo "  Expected at: $SOURCE_DIR/debian/changelog"
                ls -la "$SOURCE_DIR/" 2>/dev/null | head -10
                ls -la "$SOURCE_DIR/debian/" 2>/dev/null | head -10
                exit 1
            fi
            
            cd "$TEMP_DIR"
            DIR_NAME=$(basename "$SOURCE_DIR")
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$DIR_NAME"
            cd "$REPO_ROOT"
        fi
        
        TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)
        TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL")
        
        echo "    Created: $COMBINED_TARBALL (MD5: $TARBALL_MD5, Size: $TARBALL_SIZE bytes)"
        
        BUILD_DEPS="debhelper-compat (= 13)"
        if [[ -f "distro/debian/$PACKAGE/debian/control" ]]; then
            CONTROL_DEPS=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "distro/debian/$PACKAGE/debian/control" | \
                sed '/^Build-Depends:/s/^Build-Depends: *//' | \
                sed '/^[A-Z]/d' | \
                tr '\n' ' ' | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
            if [[ -n "$CONTROL_DEPS" && "$CONTROL_DEPS" != "" ]]; then
                BUILD_DEPS="$CONTROL_DEPS"
            fi
        fi
        
        cat > "$WORK_DIR/$PACKAGE.dsc" << EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $CHANGELOG_VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: $BUILD_DEPS
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF
        
        echo "  - Native format: using combined tarball (no _service file needed)"
    elif [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "Error: debian/ directory not found for $PACKAGE"
        exit 1
    fi
else
    if [[ "$UPLOAD_DEBIAN" == true ]]; then
        echo "  - Using quilt format (separate debian.tar.gz)"
        
        if [[ -d "distro/debian/$PACKAGE/debian" ]]; then
            echo "  - Creating debian.tar.gz"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/debian.tar.gz" -C "distro/debian/$PACKAGE" debian/
        fi
        
        if [[ -f "distro/debian/$PACKAGE/_service" ]]; then
            echo "  - Copying _service"
            cp "distro/debian/$PACKAGE/_service" "$WORK_DIR/"
        fi
        
        BUILD_DEPS="debhelper-compat (= 13)"
        if [[ -f "distro/debian/$PACKAGE/debian/control" ]]; then
            CONTROL_DEPS=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "distro/debian/$PACKAGE/debian/control" | \
                sed '/^Build-Depends:/s/^Build-Depends: *//' | \
                sed '/^[A-Z]/d' | \
                tr '\n' ' ' | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
            if [[ -n "$CONTROL_DEPS" && "$CONTROL_DEPS" != "" ]]; then
                BUILD_DEPS="$CONTROL_DEPS"
            fi
        fi
        
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
    
    if [[ "$UPLOAD_OPENSUSE" == true ]] && [[ "$SOURCE_FORMAT" != *"native"* ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
        echo "  - Note: OpenSUSE tarballs for quilt format should be handled via _service file"
        echo "  - Copying $PACKAGE.spec for OpenSUSE"
        cp "distro/opensuse/$PACKAGE.spec" "$WORK_DIR/"

        if [[ -f "$WORK_DIR/.osc/$PACKAGE.spec" ]]; then
            NEW_VERSION=$(grep "^Version:" "$WORK_DIR/$PACKAGE.spec" | awk '{print $2}' | head -1)
            NEW_RELEASE=$(grep "^Release:" "$WORK_DIR/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)
            OLD_VERSION=$(grep "^Version:" "$WORK_DIR/.osc/$PACKAGE.spec" | awk '{print $2}' | head -1)
            OLD_RELEASE=$(grep "^Release:" "$WORK_DIR/.osc/$PACKAGE.spec" | sed 's/^Release:[[:space:]]*//' | sed 's/%{?dist}//' | head -1)

            if [[ -n "${REBUILD_RELEASE:-}" ]]; then
                echo "  🔄 Using manual rebuild release number: $REBUILD_RELEASE"
                sed -i "s/^Release:[[:space:]]*${NEW_RELEASE}%{?dist}/Release:        ${REBUILD_RELEASE}%{?dist}/" "$WORK_DIR/$PACKAGE.spec"
            elif [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
                if [[ "$OLD_RELEASE" =~ ^([0-9]+) ]]; then
                    BASE_RELEASE="${BASH_REMATCH[1]}"
                    NEXT_RELEASE=$((BASE_RELEASE + 1))
                    echo "  - Detected rebuild of same version $NEW_VERSION (release $OLD_RELEASE -> $NEXT_RELEASE)"
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

cd "$WORK_DIR"

echo "==> Updating working copy"
set +e
osc up 2>&1 | tee /tmp/osc-up.log
OSC_UP_EXIT=${PIPESTATUS[0]}
set -e

if [[ $OSC_UP_EXIT -ne 0 ]]; then
    if grep -q "PackageFileConflict\|file/dir with the same name already exists" /tmp/osc-up.log 2>/dev/null; then
        echo "==> PackageFileConflict detected, resolving..."
        CONFLICTING_FILES=$(grep "failed to add file" /tmp/osc-up.log | sed "s/.*failed to add file '\([^']*\)'.*/\1/" | sort -u)
        for file in $CONFLICTING_FILES; do
            if [[ -f "$file" ]]; then
                echo "  Removing conflicting file from OBS tracking: $file"
                osc rm -f "$file" 2>/dev/null || true
            fi
        done
        echo "==> Retrying osc up after conflict resolution"
        if ! osc up; then
            echo "Error: Failed to update working copy after conflict resolution"
            exit 1
        fi
    else
        echo "Error: Failed to update working copy"
        cat /tmp/osc-up.log
        exit 1
    fi
fi
rm -f /tmp/osc-up.log

# Only auto-increment on manual runs (REBUILD_RELEASE set or not in CI), not automated workflows
OLD_DSC_FILE=""
if [[ -f "$WORK_DIR/$PACKAGE.dsc" ]]; then
    OLD_DSC_FILE="$WORK_DIR/$PACKAGE.dsc"
elif [[ -f "$WORK_DIR/.osc/sources/$PACKAGE.dsc" ]]; then
    OLD_DSC_FILE="$WORK_DIR/.osc/sources/$PACKAGE.dsc"
fi

if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ -n "$OLD_DSC_FILE" ]]; then
    OLD_DSC_VERSION=$(grep "^Version:" "$OLD_DSC_FILE" 2>/dev/null | awk '{print $2}' | head -1)
    
    IS_MANUAL=false
    if [[ -n "${REBUILD_RELEASE:-}" ]]; then
        IS_MANUAL=true
        echo "==> Manual rebuild detected (REBUILD_RELEASE=$REBUILD_RELEASE)"
    elif [[ -n "${FORCE_REBUILD:-}" ]] && [[ "${FORCE_REBUILD}" == "true" ]]; then
        IS_MANUAL=true
        echo "==> Manual workflow trigger detected (FORCE_REBUILD=true)"
    elif [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${CI:-}" ]]; then
        IS_MANUAL=true
        echo "==> Local/manual run detected (not in CI)"
    fi
    
    if [[ -n "$OLD_DSC_VERSION" ]] && [[ "$OLD_DSC_VERSION" == "$CHANGELOG_VERSION" ]] && [[ "$IS_MANUAL" == true ]]; then
        echo "==> Detected rebuild of same version $CHANGELOG_VERSION, incrementing version"
        
        # For native format, we cannot add Debian revisions (-1), so we only increment existing counters
        if [[ "$CHANGELOG_VERSION" =~ ^([0-9.]+)ppa([0-9]+)$ ]]; then
            BASE_VERSION="${BASH_REMATCH[1]}"
            PPA_NUM="${BASH_REMATCH[2]}"
            NEW_PPA_NUM=$((PPA_NUM + 1))
            NEW_VERSION="${BASE_VERSION}ppa${NEW_PPA_NUM}"
            echo "  Incrementing PPA number: $CHANGELOG_VERSION -> $NEW_VERSION"
        elif [[ "$CHANGELOG_VERSION" =~ ^([0-9.]+)\+git([0-9]+)(\.[a-f0-9]+)?(ppa([0-9]+))?$ ]]; then
            BASE_VERSION="${BASH_REMATCH[1]}"
            GIT_NUM="${BASH_REMATCH[2]}"
            GIT_HASH="${BASH_REMATCH[3]}"
            PPA_NUM="${BASH_REMATCH[5]}"
            if [[ -n "$PPA_NUM" ]]; then
                NEW_PPA_NUM=$((PPA_NUM + 1))
                NEW_VERSION="${BASE_VERSION}+git${GIT_NUM}${GIT_HASH}ppa${NEW_PPA_NUM}"
                echo "  Incrementing PPA number: $CHANGELOG_VERSION -> $NEW_VERSION"
            else
                NEW_VERSION="${BASE_VERSION}+git${GIT_NUM}${GIT_HASH}ppa1"
                echo "  Adding PPA number: $CHANGELOG_VERSION -> $NEW_VERSION"
            fi
        elif [[ "$CHANGELOG_VERSION" =~ ^([0-9.]+)(-([0-9]+))?$ ]]; then
            BASE_VERSION="${BASH_REMATCH[1]}"
            NEW_VERSION="${BASE_VERSION}ppa1"
            echo "  Warning: Native format cannot have Debian revision, converting to PPA format: $CHANGELOG_VERSION -> $NEW_VERSION"
        else
            NEW_VERSION="${CHANGELOG_VERSION}ppa1"
            echo "  Warning: Could not parse version format, appending ppa1: $CHANGELOG_VERSION -> $NEW_VERSION"
        fi
        
        REPO_CHANGELOG="$REPO_ROOT/distro/debian/$PACKAGE/debian/changelog"
        TEMP_CHANGELOG=$(mktemp)
        {
            echo "$PACKAGE ($NEW_VERSION) unstable; urgency=medium"
            echo ""
            echo "  * Rebuild to fix repository metadata issues"
            echo ""
            echo " -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
            echo ""
            if [[ -f "$REPO_CHANGELOG" ]]; then
                OLD_ENTRY_START=$(grep -n "^$PACKAGE (" "$REPO_CHANGELOG" | sed -n '2p' | cut -d: -f1)
                if [[ -n "$OLD_ENTRY_START" ]]; then
                    tail -n +$OLD_ENTRY_START "$REPO_CHANGELOG"
                fi
            fi
        } > "$TEMP_CHANGELOG"
        
        CHANGELOG_VERSION="$NEW_VERSION"
        COMBINED_TARBALL="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
        
        for old_tarball in "${PACKAGE}"_*.tar.gz; do
            if [[ -f "$old_tarball" ]] && [[ "$old_tarball" != "${PACKAGE}_${NEW_VERSION}.tar.gz" ]]; then
                echo "  Removing old tarball from OBS: $old_tarball"
                osc rm -f "$old_tarball" 2>/dev/null || rm -f "$old_tarball"
            fi
        done
        
        echo "  Recreating tarball with new version: $COMBINED_TARBALL"
        if [[ "$PACKAGE" == "matugen" ]]; then
            # Matugen: recreate tarball with updated changelog
            PKG_DIR="$TEMP_DIR/matugen-package-$$"
            mkdir -p "$PKG_DIR"
            download_service_files "$REPO_ROOT/distro/debian/$PACKAGE/_service" "$PKG_DIR" || exit 1
            cp -r "$REPO_ROOT/distro/debian/$PACKAGE/debian" "$PKG_DIR/"
            cp "$TEMP_CHANGELOG" "$PKG_DIR/debian/changelog"
            cd "$TEMP_DIR"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "matugen-package-$$"
            rm -rf "matugen-package-$$"
            cd "$WORK_DIR"
        elif [[ -d "$SOURCE_DIR" ]] && [[ -d "$SOURCE_DIR/debian" ]]; then
            SOURCE_CHANGELOG="$SOURCE_DIR/debian/changelog"
            cp "$TEMP_CHANGELOG" "$SOURCE_CHANGELOG"
            cd "$TEMP_DIR"
            DIR_NAME=$(basename "$SOURCE_DIR")
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$DIR_NAME"
            cd "$WORK_DIR"
        else
            echo "  Error: Source directory with debian/ not found for version increment"
            rm -f "$TEMP_CHANGELOG"
            exit 1
        fi
        
        rm -f "$TEMP_CHANGELOG"
        
        TARBALL_MD5=$(md5sum "$WORK_DIR/$COMBINED_TARBALL" | cut -d' ' -f1)
        TARBALL_SIZE=$(stat -c%s "$WORK_DIR/$COMBINED_TARBALL")
        
        BUILD_DEPS="debhelper-compat (= 13)"
        if [[ -f "$REPO_ROOT/distro/debian/$PACKAGE/debian/control" ]]; then
            CONTROL_DEPS=$(sed -n '/^Build-Depends:/,/^[A-Z]/p' "$REPO_ROOT/distro/debian/$PACKAGE/debian/control" | \
                sed '/^Build-Depends:/s/^Build-Depends: *//' | \
                sed '/^[A-Z]/d' | \
                tr '\n' ' ' | \
                sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\+/ /g')
            if [[ -n "$CONTROL_DEPS" && "$CONTROL_DEPS" != "" ]]; then
                BUILD_DEPS="$CONTROL_DEPS"
            fi
        fi
        
        cat > "$WORK_DIR/$PACKAGE.dsc" << EOF
Format: 3.0 (native)
Source: $PACKAGE
Binary: $PACKAGE
Architecture: any
Version: $CHANGELOG_VERSION
Maintainer: Avenge Media <AvengeMedia.US@gmail.com>
Build-Depends: $BUILD_DEPS
Files:
 $TARBALL_MD5 $TARBALL_SIZE $COMBINED_TARBALL
EOF
        echo "  - Updated changelog and recreated tarball with version $NEW_VERSION"
    fi
fi

find . -maxdepth 1 -type f \( -name "*.dsc" -o -name "*.spec" \) -exec grep -l "^<<<<<<< " {} \; 2>/dev/null | while read -r conflicted_file; do
    echo "  Removing conflicted text file: $conflicted_file"
    rm -f "$conflicted_file"
done

echo "==> Staging changes"
echo "Files to upload:"
if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh *.tar.gz *.tar.xz *.tar *.spec *.dsc _service 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_DEBIAN" == true ]]; then
    ls -lh *.tar.gz *.dsc _service 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
elif [[ "$UPLOAD_OPENSUSE" == true ]]; then
    ls -lh *.tar.gz *.tar.xz *.tar *.spec 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
fi
echo ""

osc addremove 2>&1 | grep -v "Git SCM package\|patchinfo" || true
ADDREMOVE_EXIT=${PIPESTATUS[0]}
if [[ $ADDREMOVE_EXIT -ne 0 ]] && [[ $ADDREMOVE_EXIT -ne 1 ]]; then
    echo "Warning: osc addremove returned exit code $ADDREMOVE_EXIT"
fi

if osc status 2>/dev/null | grep -q "patchinfo"; then
    echo "==> Warning: patchinfo detected, removing from commit (OBS maintenance package)"
    osc rm -f patchinfo 2>/dev/null || true
    rm -rf patchinfo 2>/dev/null || true
fi

if osc status | grep -q '^C'; then
    echo "==> Resolving conflicts"
    osc status | grep '^C' | awk '{print $2}' | xargs -r osc resolved
fi

if ! osc status 2>/dev/null | grep -qE '^[MAD]|^[?]'; then
    echo "==> No changes to commit (package already up to date)"
else
    echo "==> Committing to OBS"
    set +e
    timeout 1800 osc commit -m "$MESSAGE" 2>&1 | grep -v "Git SCM package" | grep -v "apiurl\|project\|_ObsPrj\|_manifest\|git-obs"
    COMMIT_EXIT=${PIPESTATUS[0]}
    set -e
    if [[ $COMMIT_EXIT -eq 124 ]]; then
        echo "Error: Upload timed out after 30 minutes"
        echo "  Large files may need more time. Try uploading manually:"
        echo "  cd $WORK_DIR && osc commit -m \"$MESSAGE\""
        exit 1
    elif [[ $COMMIT_EXIT -ne 0 ]]; then
        echo "Error: Upload failed with exit code $COMMIT_EXIT"
        exit 1
    fi
fi

osc results

echo ""
echo "✅ Upload complete!"
cd "$WORK_DIR"
osc results 2>&1 | head -10
cd "$REPO_ROOT"
echo ""
echo "Check build status with:"
echo "  ./distro/scripts/obs-status.sh $PACKAGE"
