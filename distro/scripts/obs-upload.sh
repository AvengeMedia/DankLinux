#!/bin/bash
# Unified OBS upload script for danklinux packages
# Handles Debian and OpenSUSE builds for both x86_64 and aarch64
# Usage: ./distro/scripts/obs-upload.sh [distro] <package-name> [commit-message|rebuild-number]
#
# Examples:
#   ./distro/scripts/obs-upload.sh cliphist "Update to v0.7.0"
#   ./distro/scripts/obs-upload.sh debian cliphist
#   ./distro/scripts/obs-upload.sh opensuse niri
#   ./distro/scripts/obs-upload.sh niri-git "Fix cargo vendor config"
#   ./distro/scripts/obs-upload.sh debian niri-git 2    # Rebuild with .db2 suffix
#   ./distro/scripts/obs-upload.sh niri-git --rebuild=2 # Rebuild with .db2 suffix (flag syntax)

set -e

# Function to strip all db suffixes (both old format db[0-9]+ and new format .db[0-9]+)
strip_db_suffixes() {
    local version="$1"
    # Strip all db suffixes (both formats)
    # This handles: db5db6db7, .db5.db6.db7, db5.db10, and any mixed combinations
    echo "$version" | sed -E 's/(\.?db[0-9]+)+$//'
}

download_service_files() {
    local service_file="$1"
    local target_dir="$2"

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

# Parameters:
#   $1 = PROJECT
#   $2 = PACKAGE
#   $3 = VERSION
#   $4 = CHECK_MODE - "commit" = check commit hash (default) - Exact version match
check_obs_version_exists() {
    local PROJECT="$1"
    local PACKAGE="$2"
    local VERSION="$3"
    local CHECK_MODE="${4:-commit}"
    local OBS_SPEC=""

    # Use osc api command
    if command -v osc &> /dev/null; then
        OBS_SPEC=$(osc api "/source/$PROJECT/$PACKAGE/${PACKAGE}.spec" 2>/dev/null || echo "")
    else
        echo "⚠️  osc command not found, skipping version check"
        return 1
    fi

    # Check if we got valid spec content
    if [[ -n "$OBS_SPEC" && "$OBS_SPEC" != *"error"* && "$OBS_SPEC" == *"Version:"* ]]; then
        OBS_VERSION=$(echo "$OBS_SPEC" | grep "^Version:" | awk '{print $2}' | xargs)

        if [[ "$CHECK_MODE" == "commit" ]] && [[ "$PACKAGE" == *"-git" ]]; then
            # Strip db suffixes before extracting commit hashes to prevent false negatives
            OBS_VERSION_CLEAN=$(strip_db_suffixes "$OBS_VERSION")
            NEW_VERSION_CLEAN=$(strip_db_suffixes "$VERSION")
            OBS_COMMIT=$(echo "$OBS_VERSION_CLEAN" | grep -oP '[a-f0-9]{8}$' || echo "")
            NEW_COMMIT=$(echo "$NEW_VERSION_CLEAN" | grep -oP '[a-f0-9]{8}$' || echo "")

            if [[ -n "$OBS_COMMIT" && -n "$NEW_COMMIT" && "$OBS_COMMIT" == "$NEW_COMMIT" ]]; then
                echo "⚠️  Commit $NEW_COMMIT already exists in OBS (current version: $OBS_VERSION)"
                return 0
            fi
        fi

        if [[ "$OBS_VERSION" == "$VERSION" ]]; then
            echo "⚠️  Version $VERSION already exists in OBS"
            return 0
        fi
    else
        echo "⚠️  Could not fetch OBS spec (API may be unavailable), proceeding anyway"
        return 1
    fi
    return 1
}

UPLOAD_DEBIAN=true
UPLOAD_OPENSUSE=true
PACKAGE=""
MESSAGE=""
REBUILD_RELEASE=""
POSITIONAL_ARGS=()

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
        --rebuild=*)
            REBUILD_RELEASE="${arg#*=}"
            ;;
        -r|--rebuild)
            REBUILD_NEXT=true
            ;;
        *)
            if [[ -n "${REBUILD_NEXT:-}" ]]; then
                REBUILD_RELEASE="$arg"
                REBUILD_NEXT=false
            else
                POSITIONAL_ARGS+=("$arg")
            fi
            ;;
    esac
done

# Check if last positional argument is a number (rebuild release)
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    LAST_INDEX=$((${#POSITIONAL_ARGS[@]} - 1))
    LAST_ARG="${POSITIONAL_ARGS[$LAST_INDEX]}"
    if [[ "$LAST_ARG" =~ ^[0-9]+$ ]] && [[ -z "$REBUILD_RELEASE" ]]; then
        # Last argument is a number and no --rebuild flag was used
        # Use it as rebuild release and remove from positional args
        REBUILD_RELEASE="$LAST_ARG"
        POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:0:$LAST_INDEX}")
    fi
fi

# Assign remaining positional args to PACKAGE and MESSAGE
if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    PACKAGE="${POSITIONAL_ARGS[0]}"
    if [[ ${#POSITIONAL_ARGS[@]} -gt 1 ]]; then
        MESSAGE="${POSITIONAL_ARGS[1]}"
    fi
fi
PROJECT="danklinux"
OBS_BASE_PROJECT="home:AvengeMedia"
OBS_BASE="$HOME/.cache/osc-checkouts"
AVAILABLE_PACKAGES=(cliphist matugen niri niri-git quickshell quickshell-git xwayland-satellite xwayland-satellite-git danksearch dgop ghostty)

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

if [[ ! -d "distro/debian/$PACKAGE" ]]; then
    echo "Error: Package '$PACKAGE' not found in distro/debian/"
    exit 1
fi

# niri stable is Debian-only (OpenSUSE uses niri-git)
if [[ "$PACKAGE" == "niri" && "$UPLOAD_OPENSUSE" == true ]]; then
    echo "==> Note: niri stable is Debian-only (openSUSE builds niri-git)"
    UPLOAD_OPENSUSE=false
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
ARTIFACT_STAGING="$TEMP_DIR/artifacts"
mkdir -p "$ARTIFACT_STAGING"
trap "rm -rf $TEMP_DIR" EXIT

echo "==> Preparing $PACKAGE for OBS upload"

find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.bz2" -o -name "*.tar" -o -name "*.spec" -o -name "_service" -o -name "*.dsc" \) -delete 2>/dev/null || true

# Remove debian.tar.gz when converting to native format
SOURCE_FORMAT_CHECK=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "")
if [[ "$SOURCE_FORMAT_CHECK" == *"native"* ]] && [[ -f "$WORK_DIR/debian.tar.gz" ]]; then
    echo "  - Removing old debian.tar.gz (converting from quilt to native format)"
    cd "$WORK_DIR"
    osc rm -f debian.tar.gz 2>/dev/null || rm -f debian.tar.gz
    cd "$REPO_ROOT"
fi

CHANGELOG_VERSION=$(grep -m1 "^$PACKAGE" distro/debian/$PACKAGE/debian/changelog 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' || echo "0.1.11-1")
SOURCE_FORMAT=$(cat "distro/debian/$PACKAGE/debian/source/format" 2>/dev/null || echo "3.0 (quilt)")

if [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ "$CHANGELOG_VERSION" == *"-"* ]]; then
    CHANGELOG_VERSION=$(echo "$CHANGELOG_VERSION" | sed 's/-[0-9]*$//')
    echo "  Warning: Removed Debian revision from version for native format: $CHANGELOG_VERSION"
fi

# Apply rebuild suffix if specified (must happen before API check)
if [[ -n "$REBUILD_RELEASE" ]] && [[ -n "$CHANGELOG_VERSION" ]]; then
    # Strip ALL db suffixes using the function
    CHANGELOG_VERSION=$(strip_db_suffixes "$CHANGELOG_VERSION")
    CHANGELOG_VERSION="${CHANGELOG_VERSION}.db${REBUILD_RELEASE}"
    echo "  - Applied rebuild suffix: $CHANGELOG_VERSION"
fi

# Check if this version already exists in OBS (unless rebuild is specified)
# Only check via spec file if package has OpenSUSE support (spec file exists locally)
if [[ -n "$CHANGELOG_VERSION" ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
    if [[ -z "$REBUILD_RELEASE" ]]; then
        if check_obs_version_exists "$OBS_PROJECT" "$PACKAGE" "$CHANGELOG_VERSION"; then
            if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                echo "==> Version $CHANGELOG_VERSION already exists in OBS, skipping upload in CI"
                exit 0
            elif [[ "$PACKAGE" == *"-git" ]]; then
                echo "==> Error: This commit is already uploaded to OBS"
                echo "    The same git commit ($(echo "$CHANGELOG_VERSION" | grep -oP '[a-f0-9]{8}' | tail -1)) already exists on OBS."
                echo "    To rebuild the same commit, specify a rebuild number:"
                echo "      ./distro/scripts/obs-upload.sh $PACKAGE 2"
                echo "      ./distro/scripts/obs-upload.sh $PACKAGE 3"
                echo "    Or push a new commit first, then run:"
                echo "      ./distro/scripts/obs-upload.sh $PACKAGE"
                exit 1
            else
                echo "==> Error: Version $CHANGELOG_VERSION already exists in OBS"
                echo "    To rebuild with a different release number, try:"
                echo "      ./distro/scripts/obs-upload.sh $PACKAGE --rebuild=2"
                echo "    or positional syntax:"
                echo "      ./distro/scripts/obs-upload.sh $PACKAGE 2"
                exit 1
            fi
        fi
    else
        # Rebuild number specified - check if this exact version already exists (exact mode)
        if check_obs_version_exists "$OBS_PROJECT" "$PACKAGE" "$CHANGELOG_VERSION" "exact"; then
            echo "==> Error: Version $CHANGELOG_VERSION already exists in OBS"
            echo "    This exact version (including .db${REBUILD_RELEASE}) is already uploaded."
            echo "    To rebuild with a different release number, try incrementing:"
            NEXT_NUM=$((REBUILD_RELEASE + 1))
            echo "      ./distro/scripts/obs-upload.sh $PACKAGE $NEXT_NUM"
            exit 1
        fi
    fi
fi

# Native format: <package>_<version>.tar.gz
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
            # Binary-download packages (danksearch, dgop): download .gz binaries directly
            elif [[ "$PACKAGE" == "danksearch" || "$PACKAGE" == "dgop" ]]; then
                echo "    Binary-download package detected: $PACKAGE"
                SOURCE_DIR="$TEMP_DIR/${PACKAGE}-${CHANGELOG_VERSION}"
                mkdir -p "$SOURCE_DIR"
                download_service_files "distro/debian/$PACKAGE/_service" "$SOURCE_DIR" || exit 1
                echo "    Downloaded binaries to $SOURCE_DIR"
            # Ghostty: download source + Zig compiler
            elif [[ "$PACKAGE" == "ghostty" ]]; then
                echo "    Ghostty package detected: downloading source and Zig compiler"
                SOURCE_DIR="$TEMP_DIR/${PACKAGE}-${CHANGELOG_VERSION}"
                mkdir -p "$SOURCE_DIR"

                # Extract URL from _service file
                SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "distro/debian/$PACKAGE/_service" | head -10)
                URL_PROTOCOL=$(echo "$SERVICE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
                URL_HOST=$(echo "$SERVICE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
                URL_PATH=$(echo "$SERVICE_BLOCK" | grep "path" | sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/' | head -1)
                SOURCE_URL="${URL_PROTOCOL}://${URL_HOST}${URL_PATH}"

                # Download Ghostty source
                echo "    Downloading Ghostty source from: $SOURCE_URL"
                if curl -L -f -s -o "$TEMP_DIR/ghostty-source.tar.gz" "$SOURCE_URL" 2>/dev/null || \
                   wget -q -O "$TEMP_DIR/ghostty-source.tar.gz" "$SOURCE_URL" 2>/dev/null; then
                    cd "$TEMP_DIR"
                    tar -xzf ghostty-source.tar.gz
                    EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "ghostty-*" ! -name "ghostty-${CHANGELOG_VERSION}" | head -1)
                    if [ -n "$EXTRACTED_DIR" ]; then
                        mv "$EXTRACTED_DIR"/* "$SOURCE_DIR/" 2>/dev/null || cp -r "$EXTRACTED_DIR"/* "$SOURCE_DIR/"
                        rm -rf "$EXTRACTED_DIR"
                    fi
                    rm -f ghostty-source.tar.gz
                    cd "$REPO_ROOT"
                else
                    echo "Error: Failed to download Ghostty source from $SOURCE_URL"
                    exit 1
                fi

                # Download Zig compilers for both architectures (OBS needs tarballs, not extracted)
                ZIG_VERSION="0.14.0"
                echo "    Downloading Zig compilers $ZIG_VERSION for x86_64 and aarch64..."
                cd "$TEMP_DIR"
                for arch in x86_64 aarch64; do
                    TARBALL="zig-linux-${arch}-${ZIG_VERSION}.tar.xz"
                    if curl -L -f -s -o "$TARBALL" "https://ziglang.org/download/$ZIG_VERSION/$TARBALL" 2>/dev/null || \
                       wget -q -O "$TARBALL" "https://ziglang.org/download/$ZIG_VERSION/$TARBALL" 2>/dev/null; then
                        cp "$TARBALL" "$SOURCE_DIR/$TARBALL"
                        # Extract x86_64 for dependency fetching
                        if [ "$arch" = "x86_64" ]; then
                            tar -xJf "$TARBALL"
                            EXTRACTED_ZIG=$(find . -maxdepth 1 -type d -name "zig-linux-*" | head -1)
                            if [ -n "$EXTRACTED_ZIG" ]; then
                                mv "$EXTRACTED_ZIG" "$SOURCE_DIR/zig"
                            fi
                            rm -rf zig-linux-*
                        fi
                    else
                        echo "Error: Failed to download Zig compiler for $arch"
                        exit 1
                    fi
                done
                cd "$REPO_ROOT"
                echo "    Zig compilers downloaded (tarballs for OBS, extracted x86_64 for deps)"

                # Download and vendor ghostty-themes - https://github.com/ghostty-org/ghostty/issues/6026
                echo "    Downloading ghostty-themes..."
                THEMES_URL="https://deps.files.ghostty.org/ghostty-themes-release-20251201-150531-bfb3ee1.tgz"
                # Use the NEW hash that matches the fixed themes tarball
                THEME_HASH="N-V-__8AANFEAwCzzNzNs3Gaq8pzGNl2BbeyFBwTyO5iZJL-"
                THEMES_SRC="$REPO_ROOT/distro/debian/ghostty/ghostty-themes.tgz"
                if [ -f "$THEMES_SRC" ]; then
                    cp "$THEMES_SRC" "$SOURCE_DIR/ghostty-themes.tgz"
                    THEMES_DL=true
                else
                    THEMES_DL=false
                    for url in "$THEMES_URL" "https://ghproxy.com/$THEMES_URL" "https://github.moeyy.xyz/$THEMES_URL"; do
                        if curl -L -f -s -o "$SOURCE_DIR/ghostty-themes.tgz" "$url" 2>/dev/null || \
                           wget -q -O "$SOURCE_DIR/ghostty-themes.tgz" "$url" 2>/dev/null; then
                            THEMES_DL=true
                            break
                        fi
                    done
                    if [ "$THEMES_DL" = false ]; then
                        echo "    Error: failed to download ghostty-themes.tgz from $THEMES_URL (and mirrors)"
                        exit 1
                    fi
                fi

                # Inject themes into zig-deps using the NEW hash
                mkdir -p "$SOURCE_DIR/zig-deps/p/$THEME_HASH"
                tar -xzf "$SOURCE_DIR/ghostty-themes.tgz" -C "$SOURCE_DIR/zig-deps/p/$THEME_HASH"
                if [[ ! -f "$SOURCE_DIR/ghostty-themes.tgz" ]]; then
                    echo "    Error: ghostty-themes.tgz missing after vendoring"
                    exit 1
                fi
                if [[ ! -d "$SOURCE_DIR/zig-deps/p/$THEME_HASH" ]] || [[ -z "$(ls -A "$SOURCE_DIR/zig-deps/p/$THEME_HASH" 2>/dev/null)" ]]; then
                    echo "    Error: vendored themes missing in zig-deps/p/$THEME_HASH"
                    exit 1
                fi
                echo "    Injected themes into zig-deps/p/$THEME_HASH"

                # Fetch Zig dependencies
                echo "    Fetching Zig dependencies..."
                cd "$SOURCE_DIR"
                export ZIG_GLOBAL_CACHE_DIR="$SOURCE_DIR/zig-deps"
                mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
                OLD_PATH="$PATH"
                export PATH="$SOURCE_DIR/zig:$PATH"
                
                # Try multiple methods to ensure all dependencies are fetched
                FETCH_SUCCESS=false
                
                # 1: Use official fetch-zig-cache.sh script
                if [ -f "nix/build-support/fetch-zig-cache.sh" ] && [ -f "build.zig.zon.txt" ]; then
                    echo "    Using official fetch-zig-cache.sh script"
                    if bash nix/build-support/fetch-zig-cache.sh 2>&1 | grep -E "Fetching:|Failed" || true; then
                        FETCH_SUCCESS=true
                    fi
                fi
                
                # Use 'zig build --fetch' to fetch all transitive dependencies
                echo "    Attempting to fetch all dependencies with 'zig build --fetch'..."
                if "$SOURCE_DIR/zig/zig" build --fetch 2>&1 | grep -v "^$" | tail -5 || true; then
                    echo "    'zig build --fetch' completed"
                    FETCH_SUCCESS=true
                fi
                
                # Manual fetching from build.zig.zon.txt as fallback
                if [ -f "build.zig.zon.txt" ]; then
                    echo "    Supplementing with manual dependency fetching from build.zig.zon.txt"
                    while IFS= read -r url; do
                        [ -z "$url" ] || [[ "$url" =~ ^[[:space:]]*# ]] && continue
                        case "$url" in
                            *ghostty-themes.tgz) continue;;
                        esac
                        "$SOURCE_DIR/zig/zig" fetch "$url" >/dev/null 2>&1 || true
                    done < "build.zig.zon.txt"
                    FETCH_SUCCESS=true
                fi
                
                DEP_COUNT=$(find zig-deps/p -maxdepth 1 -type d 2>/dev/null | wc -l)
                if [ $DEP_COUNT -gt 1 ]; then
                    echo "    Fetched $((DEP_COUNT - 1)) Zig dependencies"
                else
                    echo "    Warning: No Zig dependencies found in zig-deps/p/"
                fi
                unset ZIG_GLOBAL_CACHE_DIR
                export PATH="$OLD_PATH"

                # Remove extracted Zig (OBS will extract from tarballs per-arch during build)
                # Keep the Zig tarballs in source for debian/rules to use
                rm -rf "$SOURCE_DIR/zig"

                # Copy debian/ directory to source
                echo "    Copying debian/ packaging files to source"
                cp -r "$REPO_ROOT/distro/debian/$PACKAGE/debian" "$SOURCE_DIR/" || {
                    echo "Error: Failed to copy debian/ directory for ghostty"
                    exit 1
                }

                cd "$REPO_ROOT"
            else
                SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "distro/debian/$PACKAGE/_service" | head -10)
                URL_PROTOCOL=$(echo "$SERVICE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
                URL_HOST=$(echo "$SERVICE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
                URL_PATH=$(echo "$SERVICE_BLOCK" | grep "path" | sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/' | head -1)

                if [[ -n "$URL_PROTOCOL" && -n "$URL_HOST" && -n "$URL_PATH" ]]; then
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
    
    if [[ "$PACKAGE" == "xwayland-satellite" || "$PACKAGE" == "xwayland-satellite-git" || "$PACKAGE" == "matugen" ]] && [[ -f "$SOURCE_DIR/Cargo.toml" ]] && [[ ! -d "$SOURCE_DIR/vendor" ]]; then
        echo "    Vendoring Rust dependencies for $PACKAGE"
        cd "$SOURCE_DIR"
        if command -v cargo >/dev/null 2>&1; then
            rm -rf vendor .cargo
            mkdir -p .cargo
            cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || {
                echo "Warning: cargo vendor failed, build may fail"
            }
            if [[ -d vendor ]]; then
                echo "    Created vendor directory and .cargo/config.toml"
            fi
        else
            echo "Warning: cargo not available, vendor directory not generated"
        fi
        cd "$REPO_ROOT"
    fi
    
    if [[ "$PACKAGE" != "matugen" ]]; then
        ORIGINAL_SOURCE_DIR="$SOURCE_DIR"
    fi

    SKIP_OPENSUSE_TARBALL=false
    if [[ "$PACKAGE" == "danksearch" || "$PACKAGE" == "dgop" ]]; then
        SKIP_OPENSUSE_TARBALL=true
        echo "  - Note: $PACKAGE uses direct binary URLs, skipping tarball creation for OpenSUSE"
    fi

    if [[ -f "distro/opensuse/$PACKAGE.spec" ]] && [[ "$SKIP_OPENSUSE_TARBALL" == false ]]; then
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
                quickshell)
                    echo "    Creating $SOURCE0 (directory: quickshell-source)"
                    TARBALL_WORK=".quickshell-source-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" quickshell-source
                    tar --sort=name --mtime='2000-01-01 00:00:00' -czf "$WORK_DIR/$SOURCE0" quickshell-source
                    rm -rf quickshell-source
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                xwayland-satellite|xwayland-satellite-git)
                    echo "    Creating $SOURCE0 (directory: xwayland-satellite-source)"
                    TARBALL_WORK=".xwayland-satellite-source-work-$$"
                    cp -r "$ORIGINAL_SOURCE_DIR" "$TARBALL_WORK"
                    mv "$TARBALL_WORK" xwayland-satellite-source
                    # Vendor Rust dependencies for offline build
                    if [ -f "xwayland-satellite-source/Cargo.toml" ]; then
                        echo "    Vendoring Rust dependencies..."
                        cd xwayland-satellite-source
                        if command -v cargo >/dev/null 2>&1; then
                            rm -rf vendor .cargo
                            mkdir -p .cargo
                            cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || true
                        fi
                        cd "$OBS_TARBALL_DIR"
                    fi
                    tar --sort=name --mtime='2000-01-01 00:00:00' -czf "$WORK_DIR/$SOURCE0" xwayland-satellite-source
                    rm -rf xwayland-satellite-source
                    echo "    Created $SOURCE0 ($(stat -c%s "$WORK_DIR/$SOURCE0" 2>/dev/null || echo 0) bytes)"
                    ;;
                matugen)
                    # matugen spec has two sources: Source0 (binary) and Source1 (source with vendored deps)
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
                        MATUGEN_TEMP="$OBS_TARBALL_DIR/matugen-source-temp"
                        mkdir -p "$MATUGEN_TEMP"
                        wget -q -O "$MATUGEN_TEMP/matugen-source.tar.gz" "$SOURCE_TARBALL_URL" || {
                            echo "    Error: Failed to download source tarball"
                            exit 1
                        }
                        # Extract, vendor dependencies, and repackage
                        cd "$MATUGEN_TEMP"
                        tar -xzf matugen-source.tar.gz
                        MATUGEN_SRC_DIR=$(ls -d matugen-* 2>/dev/null | head -1)
                        if [[ -n "$MATUGEN_SRC_DIR" && -f "$MATUGEN_SRC_DIR/Cargo.toml" ]]; then
                            echo "    Vendoring Rust dependencies for aarch64 builds..."
                            cd "$MATUGEN_SRC_DIR"
                            if command -v cargo >/dev/null 2>&1; then
                                rm -rf vendor .cargo
                                mkdir -p .cargo
                                cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || true
                                if [[ -d vendor ]]; then
                                    echo "    Vendored $(ls vendor | wc -l) crates"
                                fi
                            fi
                            cd "$MATUGEN_TEMP"
                            # Rename to matugen-source for spec %setup
                            mv "$MATUGEN_SRC_DIR" matugen-source
                            tar --sort=name --mtime='2000-01-01 00:00:00' -czf "$WORK_DIR/$SOURCE1" matugen-source
                        else
                            echo "    Warning: Could not find matugen source directory, using original tarball"
                            cp matugen-source.tar.gz "$WORK_DIR/$SOURCE1"
                        fi
                        cd "$OBS_TARBALL_DIR"
                        rm -rf "$MATUGEN_TEMP"
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
                if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                    echo "  - Same version detected in CI ($NEW_VERSION), skipping upload"
                    exit 0
                else
                    echo "  - Error: Same version detected ($NEW_VERSION) but no rebuild number specified"
                    echo "    To rebuild, explicitly specify a rebuild number:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE 2"
                    echo "    or use flag syntax:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE --rebuild=2"
                    exit 1
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

    # Copy spec file for binary-download packages (OBS downloads binaries via Source URLs)
    if [[ "$SKIP_OPENSUSE_TARBALL" == true ]] && [[ -f "distro/opensuse/$PACKAGE.spec" ]]; then
        echo "  - Copying OpenSUSE spec file (no tarball needed, OBS downloads binaries directly)"
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
                if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                    echo "  - Same version detected in CI ($NEW_VERSION), skipping upload"
                    exit 0
                else
                    echo "  - Error: Same version detected ($NEW_VERSION) but no rebuild number specified"
                    echo "    To rebuild, explicitly specify a rebuild number:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE 2"
                    echo "    or use flag syntax:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE --rebuild=2"
                    exit 1
                fi
            else
                echo "  - New version detected: $OLD_VERSION -> $NEW_VERSION (keeping release $NEW_RELEASE)"
            fi
        else
            echo "  - First upload to OBS (no previous spec found)"
        fi
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
            echo "    Creating matugen combined tarball with vendored dependencies"
            # For native format, directory must be named <package>-<version>
            PKG_DIR_NAME="matugen-${CHANGELOG_VERSION}"
            PKG_DIR="$TEMP_DIR/$PKG_DIR_NAME"
            mkdir -p "$PKG_DIR"
            download_service_files "distro/debian/$PACKAGE/_service" "$PKG_DIR" || exit 1
            
            # Extract source, vendor dependencies, and repackage for aarch64 builds
            if [[ -f "$PKG_DIR/matugen-source.tar.gz" ]]; then
                echo "    Vendoring Rust dependencies for aarch64 builds..."
                cd "$PKG_DIR"
                tar -xzf matugen-source.tar.gz
                rm matugen-source.tar.gz
                MATUGEN_SRC_DIR=$(ls -d matugen-* 2>/dev/null | grep -v "\.tar\.gz" | head -1)
                if [[ -n "$MATUGEN_SRC_DIR" && -f "$MATUGEN_SRC_DIR/Cargo.toml" ]]; then
                    cd "$MATUGEN_SRC_DIR"
                    if command -v cargo >/dev/null 2>&1; then
                        rm -rf vendor .cargo
                        mkdir -p .cargo
                        cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || true
                        if [[ -d vendor ]]; then
                            echo "    Vendored $(ls vendor | wc -l) crates"
                        fi
                    fi
                    cd "$PKG_DIR"
                    # Rename to matugen-source for debian/rules
                    mv "$MATUGEN_SRC_DIR" matugen-source
                fi
                cd "$TEMP_DIR"
            fi
            
            cp -r "$REPO_ROOT/distro/debian/$PACKAGE/debian" "$PKG_DIR/"
            cd "$TEMP_DIR"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$PKG_DIR_NAME"
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
            # For native format, directory name must be <package>-<version>
            EXPECTED_DIR_NAME="${PACKAGE}-${CHANGELOG_VERSION}"
            CURRENT_DIR_NAME=$(basename "$SOURCE_DIR")
            if [[ "$CURRENT_DIR_NAME" != "$EXPECTED_DIR_NAME" ]]; then
                echo "    Renaming $CURRENT_DIR_NAME to $EXPECTED_DIR_NAME for native format"
                mv "$SOURCE_DIR" "$TEMP_DIR/$EXPECTED_DIR_NAME"
                SOURCE_DIR="$TEMP_DIR/$EXPECTED_DIR_NAME"
            fi
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
                if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                    echo "  - Same version detected in CI ($NEW_VERSION), skipping upload"
                    exit 0
                else
                    echo "  - Error: Same version detected ($NEW_VERSION) but no rebuild number specified"
                    echo "    To rebuild, explicitly specify a rebuild number:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE 2"
                    echo "    or use flag syntax:"
                    echo "      ./distro/scripts/obs-upload.sh opensuse $PACKAGE --rebuild=2"
                    exit 1
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

# Server-side cleanup via API (before osc up to prevent re-downloading old files)
echo "==> Cleaning old tarballs and .dsc files from OBS server (prevents re-uploading old versions)"
OBS_FILES=$(osc api "/source/$OBS_PROJECT/$PACKAGE" 2>/dev/null || echo "")
if [[ -n "$OBS_FILES" ]]; then
    DELETED_COUNT=0
    KEEP_CURRENT=""
    if [[ -n "$CHANGELOG_VERSION" ]]; then
        KEEP_CURRENT="${PACKAGE}_${CHANGELOG_VERSION}.tar.gz"
        echo "  Keeping current version: ${KEEP_CURRENT}"
    fi

    # Clean up old tarballs (except current version and source tarballs)
    for old_file in $(echo "$OBS_FILES" | grep -oP '(?<=name=")[^"]*\.(tar\.gz|tar\.xz|tar\.bz2)(?=")' || true); do
        if [[ "$old_file" == "$KEEP_CURRENT" ]]; then
            echo "  - Keeping: $old_file (current version)"
            continue
        fi

        # Keep source tarballs (for OpenSUSE packages - pattern: *-source.tar.*)
        if [[ "$old_file" =~ -source\.tar\.(gz|xz|bz2)$ ]]; then
            echo "  - Keeping: $old_file (source tarball for OpenSUSE)"
            continue
        fi

        echo "  - Deleting old tarball from server: $old_file"
        if osc api -X DELETE "/source/$OBS_PROJECT/$PACKAGE/$old_file" 2>/dev/null; then
            ((DELETED_COUNT++)) || true
        fi
    done

    # Clean up ALL .dsc files (they will be regenerated with correct tarball references)
    # This prevents stale .dsc files from referencing missing tarballs
    for old_dsc in $(echo "$OBS_FILES" | grep -oP '(?<=name=")[^"]*\.dsc(?=")' || true); do
        echo "  - Deleting .dsc from server: $old_dsc (will be regenerated)"
        if osc api -X DELETE "/source/$OBS_PROJECT/$PACKAGE/$old_dsc" 2>/dev/null; then
            ((DELETED_COUNT++)) || true
        fi
    done

    if [[ $DELETED_COUNT -gt 0 ]]; then
        echo "  ✓ Deleted $DELETED_COUNT old file(s) from server"
    else
        echo "  ✓ No old files to clean up"
    fi
else
    echo "  ⚠️  Could not fetch file list from server, skipping cleanup"
fi

echo "==> Staging artifacts for potential recovery..."
cp -a *.tar.gz *.tar.xz *.tar.bz2 *.tar *.spec *.dsc _service "$ARTIFACT_STAGING/" 2>/dev/null || true

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
    elif grep -q "inconsistent state" /tmp/osc-up.log 2>/dev/null; then
        echo "==> Inconsistent working copy detected, attempting repair..."
        set +e
        REPAIR_OUTPUT=$(osc repairwc . 2>&1)
        REPAIR_EXIT=$?
        set -e
        echo "$REPAIR_OUTPUT" | head -5
        
        if [[ $REPAIR_EXIT -eq 0 ]]; then
            echo "==> Retrying osc up after repair"
            if ! osc up; then
                echo "Error: Failed to update working copy after repair"
                exit 1
            fi
        else
            echo "==> Repair failed, forcing fresh checkout..."
            cd "$OBS_BASE"
            rm -rf "$OBS_PROJECT/$PACKAGE"
            osc co "$OBS_PROJECT/$PACKAGE"
            cd "$WORK_DIR"
            echo "==> Fresh checkout complete, restoring artifacts..."
            cp -a "$ARTIFACT_STAGING"/* . 2>/dev/null || true
            echo "==> Updating fresh checkout..."
            if ! osc up; then
                echo "Error: Failed to update fresh checkout"
                exit 1
            fi
        fi
    else
        echo "Error: Failed to update working copy"
        cat /tmp/osc-up.log
        exit 1
    fi
fi
rm -f /tmp/osc-up.log

# Auto-increment version on manual runs
# Prefer the server snapshot (copied before regenerating artifacts) so we do not
# compare against a freshly generated .dsc in this working tree.
if [[ -z "$OLD_DSC_FILE" ]]; then
    if [[ -f "$WORK_DIR/.osc/original/$PACKAGE.dsc" ]]; then
        OLD_DSC_FILE="$WORK_DIR/.osc/original/$PACKAGE.dsc"
    elif [[ -f "$WORK_DIR/$PACKAGE.dsc" ]]; then
        OLD_DSC_FILE="$WORK_DIR/$PACKAGE.dsc"
    fi
fi

if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ -n "$OLD_DSC_FILE" ]]; then
    OLD_DSC_VERSION=$(grep "^Version:" "$OLD_DSC_FILE" 2>/dev/null | awk '{print $2}' | head -1)
    
    IS_MANUAL=false
    IS_FORCE_UPLOAD=false

    # Check if this is a force upload (allows version increment on same version)
    if [[ "${FORCE_UPLOAD:-}" == "true" ]]; then
        IS_FORCE_UPLOAD=true
        echo "==> Force upload detected (FORCE_UPLOAD=true)"
    fi

    # Manual run detection: only truly manual runs, not scheduled CI runs
    if [[ -n "${REBUILD_RELEASE:-}" ]]; then
        IS_MANUAL=true
        echo "==> Manual rebuild detected (REBUILD_RELEASE=$REBUILD_RELEASE)"
    elif [[ -z "${GITHUB_ACTIONS:-}" ]] && [[ -z "${CI:-}" ]]; then
        IS_MANUAL=true
        echo "==> Local/manual run detected (not in CI)"
    fi

    # In CI without force_upload, treat as automated run (no version increment)
    if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
        if [[ "${IS_FORCE_UPLOAD}" != "true" ]]; then
            echo "==> Automated CI run (no force_upload) - will skip if version unchanged"
        fi
    fi
    
    if [[ -n "$OLD_DSC_VERSION" ]]; then
        # Strip db suffixes from OLD_DSC_VERSION for comparison (it might have old chained format)
        OLD_DSC_CLEAN=$(strip_db_suffixes "$OLD_DSC_VERSION")
        CHANGELOG_CLEAN=$(strip_db_suffixes "$CHANGELOG_VERSION")
        
        if [[ "$OLD_DSC_CLEAN" == "$CHANGELOG_CLEAN" ]]; then
            # In CI without force_upload, skip if version unchanged (matching DB behavior)
            if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
                if [[ "${IS_FORCE_UPLOAD}" != "true" ]] && [[ "$IS_MANUAL" != "true" ]]; then
                    echo "==> Same version detected in CI (current: $OLD_DSC_VERSION), skipping upload"
                    echo "    Use force_upload=true or set rebuild_release to override"
                    exit 0
                fi
            fi

            # Only increment version when explicitly specified via REBUILD_RELEASE
            if [[ -n "$REBUILD_RELEASE" ]]; then
                echo "==> Using specified rebuild release: .db$REBUILD_RELEASE"
                USE_REBUILD_NUM="$REBUILD_RELEASE"
            elif [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
            # In CI without rebuild_release, skip cleanly
            echo "==> Same version detected in CI (current: $CHANGELOG_VERSION), skipping upload"
            echo "    Use force_upload=true or set rebuild_release to override"
            exit 0
        else
            echo "==> Error: Same version detected ($CHANGELOG_VERSION) but no rebuild number specified"
            echo "    To rebuild, explicitly specify a rebuild number:"
            echo "      ./distro/scripts/obs-upload.sh debian $PACKAGE 2"
            echo "    or use flag syntax:"
            echo "      ./distro/scripts/obs-upload.sh debian $PACKAGE --rebuild=2"
            exit 1
        fi
        
        # Strip ALL existing db suffixes using the function
        BASE_VERSION_CLEAN=$(strip_db_suffixes "$CHANGELOG_VERSION")
        
        if [[ "$BASE_VERSION_CLEAN" =~ ^([0-9.]+)$ ]]; then
            # Simple version like 0.2.1
            NEW_VERSION="${BASE_VERSION_CLEAN}.db${USE_REBUILD_NUM}"
            echo "  Setting DB number to specified value: $CHANGELOG_VERSION -> $NEW_VERSION"
        elif [[ "$BASE_VERSION_CLEAN" =~ ^([0-9.]+)\+git([0-9]+)(\.[a-f0-9]+)?$ ]]; then
            # Git version like 0.2.1+git713.26531fc4
            BASE_VERSION="${BASH_REMATCH[1]}"
            GIT_NUM="${BASH_REMATCH[2]}"
            GIT_HASH="${BASH_REMATCH[3]:-.}"
            NEW_VERSION="${BASE_VERSION}+git${GIT_NUM}${GIT_HASH}.db${USE_REBUILD_NUM}"
            echo "  Setting DB number to specified value: $CHANGELOG_VERSION -> $NEW_VERSION"
        elif [[ "$BASE_VERSION_CLEAN" =~ ^([0-9.]+)\+git([0-9]+)$ ]]; then
            # Git version without hash like 0.2.1+git713
            BASE_VERSION="${BASH_REMATCH[1]}"
            GIT_NUM="${BASH_REMATCH[2]}"
            NEW_VERSION="${BASE_VERSION}+git${GIT_NUM}.db${USE_REBUILD_NUM}"
            echo "  Setting DB number to specified value: $CHANGELOG_VERSION -> $NEW_VERSION"
        elif [[ "$BASE_VERSION_CLEAN" =~ ^([0-9.]+)(-([0-9]+))?$ ]]; then
            # Debian format like 0.2.1-1
            BASE_VERSION="${BASH_REMATCH[1]}"
            NEW_VERSION="${BASE_VERSION}.db${USE_REBUILD_NUM}"
            echo "  Warning: Native format cannot have Debian revision, converting to DB format: $CHANGELOG_VERSION -> $NEW_VERSION"
        else
            # Fallback: just strip .db suffixes and add new one
            NEW_VERSION="${BASE_VERSION_CLEAN}.db${USE_REBUILD_NUM}"
            echo "  Setting DB number (stripped existing .db suffixes): $CHANGELOG_VERSION -> $NEW_VERSION"
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
        if [[ "$PACKAGE" == "ghostty" ]]; then
            # Ghostty: re-download source + zig + zig-deps with updated changelog
            PKG_DIR_NAME="ghostty-${NEW_VERSION}"
            PKG_DIR="$TEMP_DIR/$PKG_DIR_NAME"
            mkdir -p "$PKG_DIR"

            # Extract URL from _service file
            SERVICE_BLOCK=$(awk '/<service name="download_url">/,/<\/service>/' "$REPO_ROOT/distro/debian/$PACKAGE/_service" | head -10)
            URL_PROTOCOL=$(echo "$SERVICE_BLOCK" | grep "protocol" | sed 's/.*<param name="protocol">\(.*\)<\/param>.*/\1/' | head -1)
            URL_HOST=$(echo "$SERVICE_BLOCK" | grep "host" | sed 's/.*<param name="host">\(.*\)<\/param>.*/\1/' | head -1)
            URL_PATH=$(echo "$SERVICE_BLOCK" | grep "path" | sed 's/.*<param name="path">\(.*\)<\/param>.*/\1/' | head -1)
            SOURCE_URL="${URL_PROTOCOL}://${URL_HOST}${URL_PATH}"

            # Download and extract ghostty source
            if curl -L -f -s -o "$TEMP_DIR/ghostty-rebuild.tar.gz" "$SOURCE_URL" 2>/dev/null || \
               wget -q -O "$TEMP_DIR/ghostty-rebuild.tar.gz" "$SOURCE_URL" 2>/dev/null; then
                cd "$TEMP_DIR"
                tar -xzf ghostty-rebuild.tar.gz
                EXTRACTED=$(find . -maxdepth 1 -type d -name "ghostty-*" ! -name "$PKG_DIR_NAME" | head -1)
                if [ -n "$EXTRACTED" ]; then
                    mv "$EXTRACTED"/* "$PKG_DIR/" 2>/dev/null || cp -r "$EXTRACTED"/* "$PKG_DIR/"
                    rm -rf "$EXTRACTED"
                fi
                rm -f ghostty-rebuild.tar.gz
            fi

            # Download Zig
            ZIG_VERSION="0.14.0"
            cd "$TEMP_DIR"
            for arch in x86_64 aarch64; do
                TARBALL="zig-linux-${arch}-${ZIG_VERSION}.tar.xz"
                if curl -L -f -s -o "$TARBALL" "https://ziglang.org/download/$ZIG_VERSION/$TARBALL" 2>/dev/null || \
                   wget -q -O "$TARBALL" "https://ziglang.org/download/$ZIG_VERSION/$TARBALL" 2>/dev/null; then
                    cp "$TARBALL" "$PKG_DIR/$TARBALL"
                    if [ "$arch" = "x86_64" ]; then
                        tar -xJf "$TARBALL"
                        EXTRACTED_ZIG=$(find . -maxdepth 1 -type d -name "zig-linux-*" | head -1)
                        if [ -n "$EXTRACTED_ZIG" ]; then
                            mv "$EXTRACTED_ZIG" "$PKG_DIR/zig"
                        else
                            echo "    Warning: Zig extraction failed for $arch"
                        fi
                        rm -rf zig-linux-*
                    fi
                fi
            done
            cd "$PKG_DIR"

            # Vendor ghostty-themes (use fixed URL for Ghostty 1.2.3 - see https://github.com/ghostty-org/ghostty/issues/6026)
            THEMES_URL="https://deps.files.ghostty.org/ghostty-themes-release-20251201-150531-bfb3ee1.tgz"
            # Use the NEW hash that matches the fixed themes tarball
            THEME_HASH="N-V-__8AANFEAwCzzNzNs3Gaq8pzGNl2BbeyFBwTyO5iZJL-"
            THEMES_SRC="$REPO_ROOT/distro/debian/ghostty/ghostty-themes.tgz"
            if [ -f "$THEMES_SRC" ]; then
                cp "$THEMES_SRC" "$PKG_DIR/ghostty-themes.tgz"
                THEMES_DL=true
            else
                THEMES_DL=false
                for url in "$THEMES_URL" "https://ghproxy.com/$THEMES_URL" "https://github.moeyy.xyz/$THEMES_URL"; do
                    if curl -L -f -s -o "$PKG_DIR/ghostty-themes.tgz" "$url" 2>/dev/null || \
                       wget -q -O "$PKG_DIR/ghostty-themes.tgz" "$url" 2>/dev/null; then
                        THEMES_DL=true
                        break
                    fi
                done
                if [ "$THEMES_DL" = false ]; then
                    echo "    Error: failed to download ghostty-themes.tgz from $THEMES_URL (and mirrors)"
                    exit 1
                fi
            fi

            # Inject themes into zig-deps using the NEW hash (matches what debian/rules will set)
            mkdir -p "$PKG_DIR/zig-deps/p/$THEME_HASH"
            tar -xzf "$PKG_DIR/ghostty-themes.tgz" -C "$PKG_DIR/zig-deps/p/$THEME_HASH"
            if [[ ! -f "$PKG_DIR/ghostty-themes.tgz" ]]; then
                echo "    Error: ghostty-themes.tgz missing after vendoring"
                exit 1
            fi
            if [[ ! -d "$PKG_DIR/zig-deps/p/$THEME_HASH" ]] || [[ -z "$(ls -A "$PKG_DIR/zig-deps/p/$THEME_HASH" 2>/dev/null)" ]]; then
                echo "    Error: vendored themes missing in zig-deps/p/$THEME_HASH"
                exit 1
            fi

            # Fetch zig-deps
            export ZIG_GLOBAL_CACHE_DIR="$PKG_DIR/zig-deps"
            mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
            OLD_PATH="$PATH"
            export PATH="$PKG_DIR/zig:$PATH"
            
            FETCH_LOG="$TEMP_DIR/zig-fetch.log"
            FETCH_SUCCESS=false
            
            # Use official fetch-zig-cache.sh script
            if [ -f "nix/build-support/fetch-zig-cache.sh" ] && [ -f "build.zig.zon.txt" ]; then
                echo "    Using official fetch-zig-cache.sh script"
                bash nix/build-support/fetch-zig-cache.sh >"$FETCH_LOG" 2>&1 || true
                grep -E "Fetching:|Failed" "$FETCH_LOG" || true
                FAILED_URLS=$(grep -E "Failed to fetch:" "$FETCH_LOG" | sed 's/.*Failed to fetch: //')
                for url in $FAILED_URLS; do
                    case "$url" in
                        *ghostty-themes.tgz) echo "    Skipping ghostty-themes fetch failure; vendored tarball will be used"; continue;;
                    esac
                    echo "    Retrying Zig dep fetch: $url"
                    if ! "$PKG_DIR/zig/zig" fetch "$url" >/dev/null 2>&1; then
                        echo "    Error: failed to fetch Zig dependency $url"
                        cat "$FETCH_LOG"
                        exit 1
                    fi
                done
                FETCH_SUCCESS=true
            fi
            
            # Use 'zig build --fetch' to fetch all transitive dependencies
            echo "    Attempting to fetch all dependencies with 'zig build --fetch'..."
            cd "$PKG_DIR"
            if "$PKG_DIR/zig/zig" build --fetch 2>&1 | grep -v "^$" | tail -5 || true; then
                echo "    'zig build --fetch' completed"
                FETCH_SUCCESS=true
            fi
            
            # Always run a manual fetch pass to ensure lazy deps are present
            if [ -f "build.zig.zon.txt" ]; then
                echo "    Supplementing with manual dependency fetching from build.zig.zon.txt"
                while IFS= read -r url; do
                    [ -z "$url" ] || [[ "$url" =~ ^[[:space:]]*# ]] && continue
                    case "$url" in
                        *ghostty-themes.tgz) continue;;
                    esac
                    "$PKG_DIR/zig/zig" fetch "$url" >/dev/null 2>&1 || true
                done < "build.zig.zon.txt"
                FETCH_SUCCESS=true
            fi
            
            # Restore PATH
            export PATH="$OLD_PATH"

            DEP_COUNT=$(find "$PKG_DIR/zig-deps/p" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
            if [ "$DEP_COUNT" -lt 5 ]; then
                echo "    Warning: zig-deps seems sparse ($DEP_COUNT entries); offline build may fail"
            fi
            rm -f "$FETCH_LOG"
            unset ZIG_GLOBAL_CACHE_DIR

            # Remove Zig compiler (OBS _service downloads arch-specific binary)
            rm -rf "$PKG_DIR/zig"

            cp -r "$REPO_ROOT/distro/debian/$PACKAGE/debian" "$PKG_DIR/"
            cp "$TEMP_CHANGELOG" "$PKG_DIR/debian/changelog"
            cp "$TEMP_CHANGELOG" "$REPO_CHANGELOG"
            cd "$TEMP_DIR"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$PKG_DIR_NAME"
            rm -rf "$PKG_DIR_NAME"
            cd "$WORK_DIR"
        elif [[ "$PACKAGE" == "matugen" ]]; then
            # Matugen: recreate tarball with updated changelog and vendored dependencies
            PKG_DIR_NAME="matugen-${NEW_VERSION}"
            PKG_DIR="$TEMP_DIR/$PKG_DIR_NAME"
            mkdir -p "$PKG_DIR"
            download_service_files "$REPO_ROOT/distro/debian/$PACKAGE/_service" "$PKG_DIR" || exit 1
            
            # Extract source, vendor dependencies, and repackage for aarch64 builds
            if [[ -f "$PKG_DIR/matugen-source.tar.gz" ]]; then
                echo "    Vendoring Rust dependencies for aarch64 builds..."
                cd "$PKG_DIR"
                tar -xzf matugen-source.tar.gz
                rm matugen-source.tar.gz
                MATUGEN_SRC_DIR=$(ls -d matugen-* 2>/dev/null | grep -v "\.tar\.gz" | head -1)
                if [[ -n "$MATUGEN_SRC_DIR" && -f "$MATUGEN_SRC_DIR/Cargo.toml" ]]; then
                    cd "$MATUGEN_SRC_DIR"
                    if command -v cargo >/dev/null 2>&1; then
                        rm -rf vendor .cargo
                        mkdir -p .cargo
                        cargo vendor --versioned-dirs 2>&1 | awk '/^\[source\./ { printing=1 } printing { print }' > .cargo/config.toml || true
                        if [[ -d vendor ]]; then
                            echo "    Vendored $(ls vendor | wc -l) crates"
                        fi
                    fi
                    cd "$PKG_DIR"
                    # Rename to matugen-source for debian/rules
                    mv "$MATUGEN_SRC_DIR" matugen-source
                fi
                cd "$TEMP_DIR"
            fi
            
            cp -r "$REPO_ROOT/distro/debian/$PACKAGE/debian" "$PKG_DIR/"
            cp "$TEMP_CHANGELOG" "$PKG_DIR/debian/changelog"
            cp "$TEMP_CHANGELOG" "$REPO_CHANGELOG"
            cd "$TEMP_DIR"
            tar --sort=name --mtime='2000-01-01 00:00:00' --owner=0 --group=0 -czf "$WORK_DIR/$COMBINED_TARBALL" "$PKG_DIR_NAME"
            rm -rf "$PKG_DIR_NAME"
            cd "$WORK_DIR"
        elif [[ -d "$SOURCE_DIR" ]] && [[ -d "$SOURCE_DIR/debian" ]]; then
            SOURCE_CHANGELOG="$SOURCE_DIR/debian/changelog"
            cp "$TEMP_CHANGELOG" "$SOURCE_CHANGELOG"
            cp "$TEMP_CHANGELOG" "$REPO_CHANGELOG"
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
        fi  # Close the if [[ "$OLD_DSC_CLEAN" == "$CHANGELOG_CLEAN" ]] block
    fi  # Close the if [[ -n "$OLD_DSC_VERSION" ]] block
fi  # Close the if [[ "$UPLOAD_DEBIAN" == true ]] && [[ "$SOURCE_FORMAT" == *"native"* ]] && [[ -n "$OLD_DSC_FILE" ]] block

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
    echo "    Working directory matches OBS server state"

    # In automated CI runs, exit cleanly
    if [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${CI:-}" ]]; then
        if [[ "${IS_FORCE_UPLOAD}" != "true" ]]; then
            echo "    Skipping commit in automated run (no changes detected)"
            exit 0
        fi
    fi

    # For manual/force runs, warn but don't fail
    echo "    WARNING: Manual run with no OBS changes - this may indicate an issue"
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