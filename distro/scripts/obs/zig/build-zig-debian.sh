#!/bin/bash
# ==============================================================================
# Zig Debian Package Builder for OBS
# ==============================================================================
#
# PURPOSE:
#   Build Debian source packages for Zig binary repackaging.
#   Unlike other packages that build from source, this downloads official
#   pre-compiled Zig binaries and repackages them for Debian.
#
# HOW IT WORKS:
#   1. Downloads x86_64 and aarch64 binaries from ziglang.org
#   2. Creates orig.tar.xz containing BOTH architecture binaries
#   3. Adds debian/ packaging directory
#   4. Runs dpkg-source -b to generate:
#      - zig14_0.14.0.orig.tar.xz (upstream source with binaries)
#      - zig14_0.14.0-1.debian.tar.xz (Debian packaging files)
#      - zig14_0.14.0-1.dsc (source package descriptor with checksums)
#
# WHY THIS APPROACH:
#   - No network access during OBS builds (must include binaries)
#   - Single source package builds for both amd64 and arm64
#   - Follows Debian 3.0 (quilt) format properly
#   - dpkg-source auto-generates correct checksums in .dsc
#
# USAGE:
#   ./build-zig-debian.sh zig14 /tmp/output
#   ./build-zig-debian.sh zig15 /tmp/output
#
# ==============================================================================

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

init_common

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <zig14|zig15> [output_dir]"
    exit 1
fi

PACKAGE="$1"
OUTPUT_DIR="${2:-/tmp/zig-build}"

# Validate package
if [[ "$PACKAGE" != "zig14" && "$PACKAGE" != "zig15" ]]; then
    log_error "Package must be zig14 or zig15"
    exit 1
fi

# Version configuration
if [[ "$PACKAGE" == "zig14" ]]; then
    ZIG_VERSION="0.14.0"
    DEBIAN_VERSION="0.14.0-1"
    ZIG_X86_64_TARBALL="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
    ZIG_AARCH64_TARBALL="zig-linux-aarch64-${ZIG_VERSION}.tar.xz"
    ZIG_X86_64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_X86_64_TARBALL}"
    ZIG_AARCH64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_AARCH64_TARBALL}"
else
    ZIG_VERSION="0.15.2"
    DEBIAN_VERSION="0.15.2-1"
    ZIG_X86_64_TARBALL="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
    ZIG_AARCH64_TARBALL="zig-aarch64-linux-${ZIG_VERSION}.tar.xz"
    ZIG_X86_64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_X86_64_TARBALL}"
    ZIG_AARCH64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_AARCH64_TARBALL}"
fi

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DEBIAN_SRC_DIR="$REPO_ROOT/distro/debian/zig/$PACKAGE"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Building Debian package: $PACKAGE"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Version: $DEBIAN_VERSION"
log_info "Output: $OUTPUT_DIR"

# Create output and working directories
mkdir -p "$OUTPUT_DIR"
WORK_DIR=$(mktemp -d -t "${PACKAGE}-build-XXXXXX")
log_debug "Working directory: $WORK_DIR"

# Cleanup on exit
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$WORK_DIR"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 1: Downloading Official Zig Binaries"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Download x86_64 binary
log_info "Downloading x86_64 binary from ziglang.org..."
if ! curl -fsSL -o "$ZIG_X86_64_TARBALL" "$ZIG_X86_64_URL"; then
    log_error "Failed to download x86_64 binary"
    exit 1
fi
log_success "Downloaded $ZIG_X86_64_TARBALL ($(du -h "$ZIG_X86_64_TARBALL" | cut -f1))"

# Download aarch64 binary
log_info "Downloading aarch64 binary from ziglang.org..."
if ! curl -fsSL -o "$ZIG_AARCH64_TARBALL" "$ZIG_AARCH64_URL"; then
    log_error "Failed to download aarch64 binary"
    exit 1
fi
log_success "Downloaded $ZIG_AARCH64_TARBALL ($(du -h "$ZIG_AARCH64_TARBALL" | cut -f1))"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 2: Creating Debian orig.tar.xz"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Format: 3.0 (quilt) - orig.tar.xz + debian.tar.xz"

# Create directory for orig tarball contents
# For quilt format, orig.tar.xz should NOT contain debian/ directory
ORIG_DIR="${PACKAGE}-${ZIG_VERSION}"
mkdir -p "$ORIG_DIR"

# Copy both architecture tarballs into orig directory
# These will be extracted by debian/rules based on DEB_HOST_ARCH
cp "$ZIG_X86_64_TARBALL" "$ORIG_DIR/"
cp "$ZIG_AARCH64_TARBALL" "$ORIG_DIR/"

# Create the orig tarball (WITHOUT debian/ directory)
ORIG_TARBALL="${PACKAGE}_${ZIG_VERSION}.orig.tar.xz"
log_info "Creating $ORIG_TARBALL with both arch binaries..."

tar --sort=name \
    --mtime="2000-01-01 00:00:00" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -cJf "$ORIG_TARBALL" \
    "$ORIG_DIR"

log_success "Created orig.tar.xz: $(du -h "$ORIG_TARBALL" | cut -f1)"
log_info "  Contains: $ZIG_X86_64_TARBALL + $ZIG_AARCH64_TARBALL"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 3: Building Debian Source Package"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract orig tarball and add debian directory
tar -xf "$ORIG_TARBALL"
cd "$ORIG_DIR"

# Copy debian directory (for quilt format, this goes in debian.tar.xz)
log_info "Copying debian packaging from $DEBIAN_SRC_DIR..."
if [[ ! -d "$DEBIAN_SRC_DIR/debian" ]]; then
    log_error "Debian packaging not found: $DEBIAN_SRC_DIR/debian"
    exit 1
fi
cp -r "$DEBIAN_SRC_DIR/debian" .

# Build the source package (generates .dsc, .debian.tar.xz)
log_info "Running dpkg-source -b to generate source package..."
log_info "  This auto-generates checksums in .dsc file"

if ! dpkg-source -b . 2>&1 | tee "$WORK_DIR/dpkg-source.log"; then
    log_error "dpkg-source failed"
    cat "$WORK_DIR/dpkg-source.log"
    exit 1
fi

cd "$WORK_DIR"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 4: Copying Artifacts to Output Directory"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy .dsc, .orig.tar.xz, and .debian.tar.xz
for file in *.dsc *.orig.tar.* *.debian.tar.*; do
    if [[ -f "$file" ]]; then
        cp -v "$file" "$OUTPUT_DIR/"
        log_success "Copied: $file"
    fi
done

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Build Complete!"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Output files:"
ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

log_info ""
log_info "HOW OBS WILL BUILD THIS:"
log_info "  1. OBS extracts orig.tar.xz → binaries available"
log_info "  2. debian/rules clean → removes extracted dirs (keeps tarballs)"
log_info "  3. debian/rules configure → extracts binary for current arch"
log_info "  4. debian/rules install → installs to /usr/lib/zig-VERSION/"
log_info ""
log_info "To upload to OBS, run:"
log_info "  cd $SCRIPT_DIR/.."
log_info "  ./obs-upload.sh --distro=debian $PACKAGE $OUTPUT_DIR"

exit 0
