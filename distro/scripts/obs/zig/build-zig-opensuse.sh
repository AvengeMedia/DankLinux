#!/bin/bash
# ==============================================================================
# Zig OpenSUSE Package Builder for OBS
# ==============================================================================
#
# PURPOSE:
#   Build OpenSUSE packages for Zig binary repackaging.
#   Unlike other packages that build from source, this downloads official
#   pre-compiled Zig binaries and repackages them for OpenSUSE/RPM.
#
# HOW IT WORKS:
#   1. Downloads x86_64 and aarch64 binaries from ziglang.org
#   2. Creates simple .tar.gz with both binaries at root level
#   3. Copies .spec and -rpmlintrc files
#   4. Outputs ready-to-upload package
#
# WHY THIS APPROACH:
#   - .spec file uses %setup -q -c which creates directory and extracts into it
#   - Binaries at root level of tarball are immediately available
#   - %prep section extracts appropriate binary for current arch
#   - No compilation needed - pure binary repackaging
#
# SPEC FILE FLOW:
#   %prep:
#     - %setup -q -c creates zig14-0.14.0/ directory
#     - tar -xJf extracts zig-linux-x86_64-0.14.0.tar.xz (on x86_64)
#   %build:
#     - Nothing (binary package)
#   %install:
#     - cp -a zig-linux-x86_64-0.14.0 to /usr/lib64/zig-0.14.0
#     - ln -s to /usr/bin/zig-0.14
#
# USAGE:
#   ./build-zig-opensuse.sh zig14 /tmp/output
#   ./build-zig-opensuse.sh zig15 /tmp/output
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
    ZIG_X86_64_TARBALL="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
    ZIG_AARCH64_TARBALL="zig-linux-aarch64-${ZIG_VERSION}.tar.xz"
    ZIG_X86_64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_X86_64_TARBALL}"
    ZIG_AARCH64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_AARCH64_TARBALL}"
else
    ZIG_VERSION="0.15.2"
    ZIG_X86_64_TARBALL="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
    ZIG_AARCH64_TARBALL="zig-aarch64-linux-${ZIG_VERSION}.tar.xz"
    ZIG_X86_64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_X86_64_TARBALL}"
    ZIG_AARCH64_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_AARCH64_TARBALL}"
fi

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SPEC_FILE="$REPO_ROOT/distro/opensuse/zig/${PACKAGE}.spec"
RPMLINTRC_FILE="$REPO_ROOT/distro/opensuse/zig/${PACKAGE}-rpmlintrc"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Building OpenSUSE package: $PACKAGE"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Version: $ZIG_VERSION"
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
log_info "Step 2: Creating Source Tarball for RPM"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info ".spec uses %setup -q -c → binaries at root level"

# Create the source tarball (for OpenSUSE, use .tar.gz)
# %setup -q -c will create zig14-0.14.0/ directory and extract into it
# So we just need the binary tarballs at root level
SOURCE_TARBALL="${PACKAGE}-${ZIG_VERSION}.tar.gz"
log_info "Creating $SOURCE_TARBALL..."

tar --sort=name \
    --mtime="2000-01-01 00:00:00" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -czf "$SOURCE_TARBALL" \
    "$ZIG_X86_64_TARBALL" \
    "$ZIG_AARCH64_TARBALL"

log_success "Created source tarball: $(du -h "$SOURCE_TARBALL" | cut -f1)"
log_info "  Contains: $ZIG_X86_64_TARBALL + $ZIG_AARCH64_TARBALL"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 3: Copying Packaging Files"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy source tarball
cp -v "$SOURCE_TARBALL" "$OUTPUT_DIR/"
log_success "Copied: $SOURCE_TARBALL"

# Copy .spec file
if [[ -f "$SPEC_FILE" ]]; then
    cp -v "$SPEC_FILE" "$OUTPUT_DIR/"
    log_success "Copied: ${PACKAGE}.spec"
else
    log_error "Spec file not found: $SPEC_FILE"
    exit 1
fi

# Copy rpmlintrc file if it exists
if [[ -f "$RPMLINTRC_FILE" ]]; then
    cp -v "$RPMLINTRC_FILE" "$OUTPUT_DIR/"
    log_success "Copied: ${PACKAGE}-rpmlintrc"
    log_info "  Suppresses false positives for stdlib .h/.cpp files"
fi

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Build Complete!"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Output files:"
ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

log_info ""
log_info "HOW OBS WILL BUILD THIS:"
log_info "  %prep:"
log_info "    - %setup -q -c creates zig14-0.14.0/ and extracts tarball"
log_info "    - tar -xJf extracts binary for current architecture"
log_info "  %build:"
log_info "    - Nothing (binary package, no compilation)"
log_info "  %install:"
log_info "    - cp -a zig-linux-\${ZIG_ARCH}-VERSION to /usr/lib64/zig-VERSION"
log_info "    - ln -s creates /usr/bin/zig-VERSION symlink"
log_info ""
log_info "To upload to OBS, run:"
log_info "  cd $SCRIPT_DIR/.."
log_info "  ./obs-upload.sh --distro=opensuse $PACKAGE $OUTPUT_DIR"

exit 0
