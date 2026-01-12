#!/bin/bash
# OpenSUSE Package Builder for OBS
# Builds OpenSUSE RPM packages (.spec, source tarballs)
# All OBS-specific OpenSUSE build logic is contained here

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/version.sh
source "$SCRIPT_DIR/lib/version.sh"
# shellcheck source=./lib/package-config.sh
source "$SCRIPT_DIR/lib/package-config.sh"
# shellcheck source=./lib/api.sh
source "$SCRIPT_DIR/lib/api.sh"
# shellcheck source=./lib/hash.sh
source "$SCRIPT_DIR/lib/hash.sh"

# Initialize
init_common

# Repository root
REPO_ROOT=$(get_repo_root)

# Usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] PACKAGE VERSION OUTPUT_DIR

Build OpenSUSE RPM source package for OBS.

ARGUMENTS:
  PACKAGE       Package name (e.g., niri-git)
  VERSION       Version string (e.g., 25.11+git2576.7c089857)
  OUTPUT_DIR    Directory to output build artifacts

OPTIONS:
  --rebuild=N   Rebuild number (modifies Release field)
  --dry-run     Prepare but don't build
  --verbose     Enable verbose output
  -h, --help    Show this help message

EXAMPLES:
  $(basename "$0") niri-git 25.11+git2576.7c089857 /tmp/build
  $(basename "$0") --rebuild=2 ghostty 1.0.0 /tmp/build

EOF
    exit 0
}

# Parse arguments
REBUILD_NUM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild=*)
            REBUILD_NUM="${1#*=}"
            shift
            ;;
        --verbose|-v)
            DEBUG=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            break
            ;;
    esac
done

# Required arguments
PACKAGE="${1:-}"
VERSION="${2:-}"
OUTPUT_DIR="${3:-}"

if [[ -z "$PACKAGE" || -z "$VERSION" || -z "$OUTPUT_DIR" ]]; then
    log_error "Missing required arguments"
    usage
fi

# Validate package exists
if ! validate_package "$PACKAGE"; then
    log_error "Package not found: $PACKAGE"
    exit $ERR_CONFIG
fi

# Check if package supports OpenSUSE
if ! package_supports_distro "$PACKAGE" "opensuse"; then
    log_error "$PACKAGE does not support OpenSUSE builds"
    exit $ERR_CONFIG
fi

log_info "Building OpenSUSE package: $PACKAGE"
log_info "Version: $VERSION"
log_info "Output: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get package configuration
PACKAGE_TYPE=$(get_package_type "$PACKAGE")
UPSTREAM_REPO=$(get_upstream_repo "$PACKAGE")
BUILD_LANGUAGE=$(get_build_language "$PACKAGE")

# Create temp working directory
WORK_DIR=$(create_temp_dir)
log_debug "Working directory: $WORK_DIR"

# OpenSUSE spec file
SPEC_FILE="$REPO_ROOT/distro/opensuse/${PACKAGE}.spec"

if [[ ! -f "$SPEC_FILE" ]]; then
    log_error "Spec file not found: $SPEC_FILE"
    exit $ERR_CONFIG
fi

# Extract base version (without .db suffix) for source fetching
BASE_VERSION=$(strip_db_suffixes "$VERSION")
COMMIT_HASH=$(extract_commit_hash "$BASE_VERSION" 2>/dev/null || echo "")

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Preparing source code"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Prepare source based on package type
SOURCE_DIR="$WORK_DIR/${PACKAGE}-source"
mkdir -p "$SOURCE_DIR"

# Treat stable packages with commit hashes (pinned) as git packages
if [[ "$PACKAGE_TYPE" == "git" ]] || [[ -n "$COMMIT_HASH" ]]; then
    # Git package or pinned stable package: clone at specific commit
    log_info "Cloning from $UPSTREAM_REPO at commit $COMMIT_HASH..."

    BRANCH=$(get_upstream_branch "$PACKAGE")

    if ! git clone --quiet "https://github.com/$UPSTREAM_REPO.git" "$SOURCE_DIR" 2>/dev/null; then
        log_error "Failed to clone repository: $UPSTREAM_REPO"
        exit $ERR_NETWORK
    fi

    cd "$SOURCE_DIR"

    # Checkout specific commit if we have a hash
    if [[ -n "$COMMIT_HASH" ]]; then
        if ! git checkout "$COMMIT_HASH" 2>/dev/null; then
            log_error "Failed to checkout commit: $COMMIT_HASH"
            exit $ERR_BUILD_FAILURE
        fi

        # Verify hash matches
        if ! verify_git_source_hash "$PACKAGE" "$COMMIT_HASH" "$SOURCE_DIR"; then
            exit $ERR_HASH_MISMATCH
        fi
    fi

    # Vendor dependencies for Rust packages
    if [[ "$BUILD_LANGUAGE" == "rust" ]] && requires_vendor_deps "$PACKAGE"; then
        log_info "Vendoring Rust dependencies..."

        # Vendor dependencies before removing .git directory
        if ! cargo vendor --versioned-dirs --sync Cargo.toml > cargo-vendor-config.txt; then
            log_error "Failed to vendor Rust dependencies"
            rm -f cargo-vendor-config.txt
            exit $ERR_BUILD_FAILURE
        fi

        mkdir -p .cargo

        # Extract [source.*] sections from vendor output
        if [[ -s cargo-vendor-config.txt ]]; then
            awk '/^\[source\./ { printing=1 } printing { print }' cargo-vendor-config.txt > .cargo/config.toml
            rm -f cargo-vendor-config.txt
        fi

        # Fallback if config not created
        if [[ ! -s .cargo/config.toml ]]; then
            cat > .cargo/config.toml <<EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF
        fi

        log_success "Vendored dependencies created"
    fi

    # Remove .git directory for source package
    rm -rf .git

    cd "$WORK_DIR"

else
    # Stable package: download release tarball
    rm -rf "$SOURCE_DIR"

    log_info "Downloading release $BASE_VERSION from $UPSTREAM_REPO..."

    SOURCE_TYPE=$(get_source_type "$PACKAGE")

    if [[ "$SOURCE_TYPE" == "custom" ]]; then
        # Custom URL template
        URL_TEMPLATE=$(get_url_template "$PACKAGE")
        DOWNLOAD_URL="${URL_TEMPLATE//\{version\}/$BASE_VERSION}"
    else
        # GitHub release - try multiple URL patterns
        DOWNLOAD_URL="https://github.com/$UPSTREAM_REPO/releases/download/v${BASE_VERSION}/${PACKAGE}-${BASE_VERSION}.tar.gz"

        # Try without 'v' prefix if first attempt fails
        if ! curl -sL -f -I "$DOWNLOAD_URL" &>/dev/null; then
            DOWNLOAD_URL="https://github.com/$UPSTREAM_REPO/releases/download/${BASE_VERSION}/${PACKAGE}-${BASE_VERSION}.tar.gz"

            # Try GitHub's automatic source archive as final fallback
            if ! curl -sL -f -I "$DOWNLOAD_URL" &>/dev/null; then
                log_info "Release tarball not found, using GitHub source archive..."
                DOWNLOAD_URL="https://github.com/$UPSTREAM_REPO/archive/refs/tags/v${BASE_VERSION}.tar.gz"

                # Try without 'v' prefix for source archive too
                if ! curl -sL -f -I "$DOWNLOAD_URL" &>/dev/null; then
                    DOWNLOAD_URL="https://github.com/$UPSTREAM_REPO/archive/refs/tags/${BASE_VERSION}.tar.gz"
                fi
            fi
        fi
    fi

    log_debug "Download URL: $DOWNLOAD_URL"

    TARBALL="$WORK_DIR/$(basename "$DOWNLOAD_URL")"

    if ! download_file_with_retry "$DOWNLOAD_URL" "$TARBALL"; then
        log_error "Failed to download source tarball"
        exit $ERR_NETWORK
    fi

    # Verify tarball integrity
    if ! verify_tarball_integrity "$TARBALL"; then
        exit $ERR_BUILD_FAILURE
    fi

    # Extract tarball
    log_info "Extracting source tarball..."
    tar -xf "$TARBALL" -C "$WORK_DIR"

    # Find extracted directory
    EXTRACTED_DIR=$(find "$WORK_DIR" -maxdepth 1 -type d -name "${PACKAGE}*" | grep -v "^$WORK_DIR$" | head -1)

    if [[ -z "$EXTRACTED_DIR" ]]; then
        log_error "Failed to find extracted source directory"
        exit $ERR_BUILD_FAILURE
    fi

    mv "$EXTRACTED_DIR" "$SOURCE_DIR"

    # Remove the downloaded tarball to prevent it from being included in build artifacts
    rm -f "$TARBALL"

    # Vendor Rust dependencies if required
    BUILD_LANGUAGE=$(get_build_language "$PACKAGE")

    if [[ "$BUILD_LANGUAGE" == "rust" ]] && requires_vendor_deps "$PACKAGE"; then
        log_info "Vendoring Rust dependencies..."
        
        cd "$SOURCE_DIR"

        # Run cargo vendor and capture only stdout (config), let stderr show progress
        if ! cargo vendor --versioned-dirs --sync Cargo.toml > cargo-vendor-config.txt; then
            log_error "Failed to vendor Rust dependencies"
            rm -f cargo-vendor-config.txt
            exit $ERR_BUILD_FAILURE
        fi

        mkdir -p .cargo

        # Extract [source.*] sections from vendor output
        if [[ -s cargo-vendor-config.txt ]]; then
            awk '/^\[source\./ { printing=1 } printing { print }' cargo-vendor-config.txt > .cargo/config.toml
            rm -f cargo-vendor-config.txt
        fi

        # Fallback if config not created
        if [[ ! -s .cargo/config.toml ]]; then
            cat > .cargo/config.toml <<EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF
        fi

        log_success "Vendored dependencies created"
        
        cd "$WORK_DIR"
    fi
fi

log_success "Source prepared: $(du -sh "$SOURCE_DIR" | cut -f1)"

# Special handling for Ghostty: vendor Zig dependencies
if [[ "$PACKAGE" == "ghostty" ]]; then
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Vendoring Ghostty Zig dependencies"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cd "$SOURCE_DIR"

    # Download ghostty-themes.tgz
    THEME_URL="https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/release-20251201-150531-bfb3ee1/ghostty-themes.tgz"
    log_info "Downloading ghostty-themes.tgz..."
    if ! download_file_with_retry "$THEME_URL" "ghostty-themes.tgz"; then
        log_error "Failed to download ghostty-themes.tgz"
        exit $ERR_NETWORK
    fi
    log_success "Downloaded ghostty-themes.tgz"

    # Patch build.zig.zon to use the downloaded themes using Dec 2025 release
    log_info "Patching build.zig.zon to use local themes..."
    THEMES_FILE="file://$SOURCE_DIR/ghostty-themes.tgz"
    sed -i "s|https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/.\+/ghostty-themes.tgz|${THEMES_FILE}|" "$SOURCE_DIR/build.zig.zon"
    sed -i '/\.iterm2_themes/,/}/ s|\.hash = "[^"]\+"|.hash = "N-V-__8AANFEAwCzzNzNs3Gaq8pzGNl2BbeyFBwTyO5iZJL-"|' "$SOURCE_DIR/build.zig.zon"

    # Vendor Zig dependencies by running a fetch-only build
    log_info "Fetching Zig dependencies..."
    mkdir -p zig-deps/p
    export ZIG_GLOBAL_CACHE_DIR="$SOURCE_DIR/zig-deps"

    # Use zig to fetch dependencies (must use Zig 0.14 for compatibility with OBS builds)
    ZIG_BIN=""
    if command -v zig-0.14 &> /dev/null; then
        ZIG_BIN="zig-0.14"
    elif command -v /usr/bin/zig-0.14 &> /dev/null; then
        ZIG_BIN="/usr/bin/zig-0.14"
    elif [ -x "/tmp/zig-linux-x86_64-0.14.0/zig" ]; then
        ZIG_BIN="/tmp/zig-linux-x86_64-0.14.0/zig"
    fi

    if [ -z "$ZIG_BIN" ]; then
        log_info "Zig 0.14 not found - downloading to /tmp..."
        cd /tmp
        if ! curl -LO https://ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz; then
            log_error "Failed to download Zig 0.14.0"
            exit $ERR_BUILD_FAILURE
        fi
        if ! tar -xJf zig-linux-x86_64-0.14.0.tar.xz; then
            log_error "Failed to extract Zig 0.14.0"
            exit $ERR_BUILD_FAILURE
        fi
        ZIG_BIN="/tmp/zig-linux-x86_64-0.14.0/zig"
        cd "$SOURCE_DIR"
        log_success "Downloaded and extracted Zig 0.14.0 to /tmp"
    fi

    log_info "Using $ZIG_BIN to vendor dependencies..."
    # Run build to populate cache with ALL dependencies (deps are cached)
    $ZIG_BIN build -Doptimize=ReleaseFast 2>&1 | grep -v "^info:" || true
    log_success "Vendored Zig dependencies: $(du -sh zig-deps | cut -f1)"

    cd "$WORK_DIR"
fi

# Create source tarball
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Creating source tarball"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get tarball configuration
TARBALL_DIR=$(get_tarball_directory "$PACKAGE")
TARBALL_COMPRESSION=$(get_tarball_compression "$PACKAGE")
TARBALL_OPTIONS=(--sort=name --mtime=2000-01-01 --owner=0 --group=0)

# Substitute version in directory name template
TARBALL_DIR="${TARBALL_DIR//\{version\}/$BASE_VERSION}"

log_debug "Tarball directory name: $TARBALL_DIR"
log_debug "Tarball compression: $TARBALL_COMPRESSION"

# Rename source directory to match tarball directory name (only if different)
if [[ "$(basename "$SOURCE_DIR")" != "$TARBALL_DIR" ]]; then
    log_debug "Renaming $(basename "$SOURCE_DIR") to $TARBALL_DIR"
    mv "$SOURCE_DIR" "$WORK_DIR/$TARBALL_DIR"
    SOURCE_DIR="$WORK_DIR/$TARBALL_DIR"
else
    log_debug "Directory name already matches: $TARBALL_DIR"
fi

# Determine tarball filename from directory name (matches Source0 in spec)
case "$TARBALL_COMPRESSION" in
    none)
        TARBALL_NAME="${TARBALL_DIR}.tar"
        ;;
    gz)
        TARBALL_NAME="${TARBALL_DIR}.tar.gz"
        ;;
    xz)
        TARBALL_NAME="${TARBALL_DIR}.tar.xz"
        ;;
    bz2)
        TARBALL_NAME="${TARBALL_DIR}.tar.bz2"
        ;;
    *)
        log_error "Unknown compression type: $TARBALL_COMPRESSION"
        exit $ERR_CONFIG
        ;;
esac

TARBALL_PATH="$OUTPUT_DIR/${TARBALL_NAME}"

# Create tarball based on compression type
case "$TARBALL_COMPRESSION" in
    none)
        log_info "Creating uncompressed tarball: $TARBALL_NAME"
        tar "${TARBALL_OPTIONS[@]}" -cf "$TARBALL_PATH" -C "$WORK_DIR" "$TARBALL_DIR"
        ;;
    gz)
        log_info "Creating gzip tarball: $TARBALL_NAME"
        tar "${TARBALL_OPTIONS[@]}" -czf "$TARBALL_PATH" -C "$WORK_DIR" "$TARBALL_DIR"
        ;;
    xz)
        log_info "Creating xz tarball: $TARBALL_NAME"
        tar "${TARBALL_OPTIONS[@]}" -cJf "$TARBALL_PATH" -C "$WORK_DIR" "$TARBALL_DIR"
        ;;
    bz2)
        log_info "Creating bzip2 tarball: $TARBALL_NAME"
        tar "${TARBALL_OPTIONS[@]}" -cjf "$TARBALL_PATH" -C "$WORK_DIR" "$TARBALL_DIR"
        ;;
esac

log_success "Tarball created: $(basename "$TARBALL_PATH") ($(du -h "$TARBALL_PATH" | cut -f1))"

# Copy and update spec file
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Preparing spec file"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

OUTPUT_SPEC="$OUTPUT_DIR/${PACKAGE}.spec"
cp "$SPEC_FILE" "$OUTPUT_SPEC"

# Update Version field
sed -i "s/^Version:.*/Version:        $BASE_VERSION/" "$OUTPUT_SPEC"

# Update Release field for rebuilds
if [[ -n "$REBUILD_NUM" ]]; then
    sed -i "s/^Release:.*/Release:        ${REBUILD_NUM}%{?dist}/" "$OUTPUT_SPEC"
    log_info "Updated Release field to: $REBUILD_NUM"
else
    sed -i "s/^Release:.*/Release:        1%{?dist}/" "$OUTPUT_SPEC"
fi

log_info "Updated Version field to: $BASE_VERSION"

# Add changelog entry
CHANGELOG_DATE=$(date "+%a %b %d %Y")
CHANGELOG_ENTRY="* $CHANGELOG_DATE Avenge Media <AvengeMedia.US@gmail.com> - ${BASE_VERSION}-${REBUILD_NUM:-1}"

if [[ -n "$REBUILD_NUM" ]]; then
    CHANGELOG_MESSAGE="- Rebuild #$REBUILD_NUM"
elif [[ "$PACKAGE_TYPE" == "git" ]]; then
    COMMIT_COUNT=$(echo "$BASE_VERSION" | grep -oP '\+git\K[0-9]+' || echo "")
    CHANGELOG_MESSAGE="- Git snapshot (commit $COMMIT_COUNT: $COMMIT_HASH)"
else
    CHANGELOG_MESSAGE="- Update to upstream version $BASE_VERSION"
fi

# Insert changelog entry after %changelog line
sed -i "/%changelog/a\\$CHANGELOG_ENTRY\\n$CHANGELOG_MESSAGE" "$OUTPUT_SPEC"

log_success "Spec file updated"

# Copy _service file if it exists
SERVICE_FILE="$REPO_ROOT/distro/opensuse/_service"
if [[ -f "$SERVICE_FILE" ]]; then
    cp "$SERVICE_FILE" "$OUTPUT_DIR/"
    log_debug "Copied _service file"
fi

# List output files
log_success "Build complete!"
log_info "Output files:"
ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

# Generate build metadata
generate_build_metadata "$PACKAGE" "$VERSION" "$SOURCE_DIR" "$TARBALL_PATH" > "$OUTPUT_DIR/build-metadata.json"

log_success "OpenSUSE build completed successfully"
