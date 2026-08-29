#!/bin/bash
# ==============================================================================
# Rust Debian Package Builder for OBS
# ==============================================================================
#
# Repackages official Rust standalone toolchains (same idea as zig14):
#   1. Download x86_64 and aarch64 tarballs from static.rust-lang.org
#   2. Pack both into a 3.0 (quilt) orig.tar.xz
#   3. debian/rules extracts the current-arch toolchain at OBS build time
#
# Debian 13 rustc is 1.85; niri 26.4 requires rustc 1.87. OBS has no network
# during the package build, so the binaries must be in the source package.
#
# Usage:
#   ./build-rust-debian.sh rust187 /tmp/output
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

init_common

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <rust187> [output_dir]"
    exit 1
fi

PACKAGE="$1"
OUTPUT_DIR="${2:-/tmp/rust-build}"

if [[ "$PACKAGE" != "rust187" ]]; then
    log_error "Package must be rust187"
    exit 1
fi

RUST_VERSION="1.87.0"
DEBIAN_VERSION="${RUST_VERSION}-1"
# Component tarballs (rustc+cargo+std) are much smaller than the full
# rust-VERSION-ARCH bundle, which also ships docs/clippy/rustfmt.
RUST_COMPONENTS=(rustc cargo rust-std)
RUST_ARCHES=(x86_64 aarch64)

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DEBIAN_SRC_DIR="$REPO_ROOT/distro/debian/${PACKAGE}"
RUST_DL_CACHE="${RUST_CACHE_DIR:-$HOME/.cache/danklinux-${PACKAGE}}"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Building Debian package: $PACKAGE"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Version: $DEBIAN_VERSION"
log_info "Output: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR" "$RUST_DL_CACHE"
WORK_DIR=$(mktemp -d -t "${PACKAGE}-build-XXXXXX")
log_debug "Working directory: $WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$WORK_DIR"

download_cached() {
    local url="$1"
    local name="$2"
    if [[ -f "$RUST_DL_CACHE/$name" ]]; then
        log_info "Using cached $name"
        cp "$RUST_DL_CACHE/$name" "$name"
        return 0
    fi
    log_info "Downloading $name..."
    if ! curl -fL --retry 3 --retry-delay 2 -o "$name" "$url"; then
        log_error "Failed to download $name"
        return 1
    fi
    cp "$name" "$RUST_DL_CACHE/$name"
    log_success "Downloaded $name ($(du -h "$name" | cut -f1))"
}

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 1: Downloading Official Rust Toolchains"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for arch in "${RUST_ARCHES[@]}"; do
    for comp in "${RUST_COMPONENTS[@]}"; do
        name="${comp}-${RUST_VERSION}-${arch}-unknown-linux-gnu.tar.xz"
        download_cached "https://static.rust-lang.org/dist/${name}" "$name"
    done
done

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 2: Creating Debian orig.tar.xz"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ORIG_DIR="${PACKAGE}-${RUST_VERSION}"
mkdir -p "$ORIG_DIR"
for arch in "${RUST_ARCHES[@]}"; do
    for comp in "${RUST_COMPONENTS[@]}"; do
        cp "${comp}-${RUST_VERSION}-${arch}-unknown-linux-gnu.tar.xz" "$ORIG_DIR/"
    done
done

ORIG_TARBALL="${PACKAGE}_${RUST_VERSION}.orig.tar.xz"
log_info "Creating $ORIG_TARBALL with both arch toolchains..."

tar --sort=name \
    --mtime="2000-01-01 00:00:00" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -cJf "$ORIG_TARBALL" \
    "$ORIG_DIR"

log_success "Created orig.tar.xz: $(du -h "$ORIG_TARBALL" | cut -f1)"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 3: Building Debian Source Package"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

tar -xf "$ORIG_TARBALL"
cd "$ORIG_DIR"

if [[ ! -d "$DEBIAN_SRC_DIR/debian" ]]; then
    log_error "Debian packaging not found: $DEBIAN_SRC_DIR/debian"
    exit 1
fi
cp -r "$DEBIAN_SRC_DIR/debian" .

if ! dpkg-source -b . 2>&1 | tee "$WORK_DIR/dpkg-source.log"; then
    log_error "dpkg-source failed"
    cat "$WORK_DIR/dpkg-source.log"
    exit 1
fi

cd "$WORK_DIR"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Step 4: Copying Artifacts"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for file in *.dsc *.orig.tar.* *.debian.tar.*; do
    if [[ -f "$file" ]]; then
        cp -v "$file" "$OUTPUT_DIR/"
        log_success "Copied: $file"
    fi
done

log_info "Output files:"
ls -lh "$OUTPUT_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
log_info "Upload with: ./obs-upload.sh --distro=debian $PACKAGE $OUTPUT_DIR"

exit 0
