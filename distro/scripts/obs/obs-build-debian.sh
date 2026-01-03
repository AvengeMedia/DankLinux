#!/bin/bash
# Debian Package Builder for OBS
# Builds Debian source packages (.dsc, .tar.xz, .debian.tar.xz)
# All OBS-specific Debian build logic is contained here

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

Build Debian source package for OBS.

ARGUMENTS:
  PACKAGE       Package name (e.g., niri-git)
  VERSION       Version string (e.g., 25.11+git2576.7c089857)
  OUTPUT_DIR    Directory to output build artifacts

OPTIONS:
  --rebuild=N   Rebuild number (adds .dbN suffix)
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
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild=*)
            REBUILD_NUM="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Check if package supports Debian
if ! package_supports_distro "$PACKAGE" "debian"; then
    log_error "$PACKAGE does not support Debian builds"
    exit $ERR_CONFIG
fi

log_info "Building Debian package: $PACKAGE"
log_info "Version: $VERSION"
log_info "Output: $OUTPUT_DIR"

# Apply rebuild suffix if specified
if [[ -n "$REBUILD_NUM" ]]; then
    VERSION=$(increment_db_version "$VERSION" "$REBUILD_NUM")
    log_info "Rebuild version: $VERSION"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get package configuration
PACKAGE_TYPE=$(get_package_type "$PACKAGE")
UPSTREAM_REPO=$(get_upstream_repo "$PACKAGE")

# Create temp working directory
WORK_DIR=$(create_temp_dir)
log_debug "Working directory: $WORK_DIR"

# Debian package directory
DEBIAN_SRC_DIR="$REPO_ROOT/distro/debian/$PACKAGE"

if [[ ! -d "$DEBIAN_SRC_DIR/debian" ]]; then
    log_error "Debian packaging not found: $DEBIAN_SRC_DIR/debian"
    exit $ERR_CONFIG
fi

# Determine source format
SOURCE_FORMAT=$(cat "$DEBIAN_SRC_DIR/debian/source/format" 2>/dev/null || echo "3.0 (native)")
log_debug "Source format: $SOURCE_FORMAT"

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

    # Vendor Rust dependencies if required
    BUILD_LANGUAGE=$(get_build_language "$PACKAGE")

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

# Copy debian/ directory into source
log_info "Copying debian/ packaging..."
cp -r "$DEBIAN_SRC_DIR/debian" "$SOURCE_DIR/"

# Update debian/changelog with new version
log_info "Updating debian/changelog to version $VERSION..."

CHANGELOG="$SOURCE_DIR/debian/changelog"
SOURCE_NAME=$(head -1 "$CHANGELOG" | cut -d' ' -f1)

TEMP_CHANGELOG=$(mktemp)
{
    echo "$SOURCE_NAME ($VERSION) unstable; urgency=medium"
    echo ""
    if [[ -n "$REBUILD_NUM" ]]; then
        echo "  * Rebuild #$REBUILD_NUM"
    elif [[ "$PACKAGE_TYPE" == "git" ]]; then
        COMMIT_COUNT=$(echo "$BASE_VERSION" | grep -oP '\+git\K[0-9]+' || echo "")
        echo "  * Git snapshot (commit $COMMIT_COUNT: $COMMIT_HASH)"
    else
        echo "  * Update to upstream version $BASE_VERSION"
    fi
    echo ""
    echo " -- Avenge Media <AvengeMedia.US@gmail.com>  $(date -R)"
    echo ""
    cat "$CHANGELOG"
} > "$TEMP_CHANGELOG"

mv "$TEMP_CHANGELOG" "$CHANGELOG"

log_success "Changelog updated"

# Build source package
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Building Debian source package"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "Dry-run mode: Skipping actual build"
    log_info "Source prepared at: $SOURCE_DIR"
    exit 0
fi

cd "$SOURCE_DIR"

# Build source package with dpkg-source
if [[ "$SOURCE_FORMAT" == "3.0 (native)" ]]; then
    log_info "Building native source package..."

    if ! dpkg-source -b . 2>&1 | tee "$WORK_DIR/build.log"; then
        log_error "dpkg-source build failed"
        log_error "Build log: $WORK_DIR/build.log"
        exit $ERR_BUILD_FAILURE
    fi

else
    log_info "Building quilt source package..."

    # For quilt format, we need separate orig tarball
    # This is handled by _service file on OBS side
    # Just prepare debian.tar.xz

    if ! dpkg-source -b . 2>&1 | tee "$WORK_DIR/build.log"; then
        log_error "dpkg-source build failed"
        log_error "Build log: $WORK_DIR/build.log"
        exit $ERR_BUILD_FAILURE
    fi
fi

cd "$WORK_DIR"

# Move built files to output directory
log_info "Moving build artifacts to output directory..."

find "$WORK_DIR" -maxdepth 1 -type f \( -name "*.dsc" -o -name "*.tar.*" -o -name "*.debian.tar.*" \) -exec mv {} "$OUTPUT_DIR/" \;

# Also copy _service file if it exists (for OBS source service)
if [[ -f "$DEBIAN_SRC_DIR/_service" ]]; then
    log_debug "Copying _service file..."
    cp "$DEBIAN_SRC_DIR/_service" "$OUTPUT_DIR/"
fi

# List output files
log_success "Build complete!"
log_info "Output files:"
ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

# Generate build metadata
generate_build_metadata "$PACKAGE" "$VERSION" "$SOURCE_DIR" "" > "$OUTPUT_DIR/build-metadata.json"

log_success "Debian build completed successfully"
