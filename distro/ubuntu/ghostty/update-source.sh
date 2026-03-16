#!/bin/bash
# Script to update Ghostty source, bundle Zig, and vendor dependencies for Launchpad builds
# Usage: ./update-source.sh [version-tag]

set -e

PACKAGE_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_NAME="ghostty"
DEBIAN_DIR="$PACKAGE_DIR/debian"

# Default to latest stable from GitHub if not specified
if [ -z "$1" ]; then
    echo "Getting latest version tag from GitHub..."
    VERSION=$(git ls-remote --tags --refs --sort='-v:refname' https://github.com/ghostty-org/ghostty.git | head -n1 | awk -F/ '{print $NF}' | sed 's/^v//')
else
    VERSION="$1"
fi

echo "Updating to Ghostty version: $VERSION"

# Setup temp directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Working in: $WORK_DIR"
cd "$WORK_DIR"

# Download Ghostty Source from official release
echo "Downloading Ghostty source..."
RELEASE_URL="https://release.files.ghostty.org/${VERSION}/ghostty-${VERSION}.tar.gz"
wget -q -O ghostty-source.tar.gz "$RELEASE_URL"

if [ ! -f ghostty-source.tar.gz ]; then
    echo "ERROR: Failed to download Ghostty source from $RELEASE_URL"
    exit 1
fi

echo "Extracting Ghostty source..."
mkdir -p ghostty-source
tar -xzf ghostty-source.tar.gz -C ghostty-source --strip-components=1
rm ghostty-source.tar.gz

cd ghostty-source

# Bundle Zig 0.15.2 so Launchpad does not depend on archive zig versions.
ZIG_VERSION="0.15.2"
ZIG_URL_X86_64="https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz"
ZIG_URL_AARCH64="https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz"

echo "Bundling Zig version: $ZIG_VERSION"
mkdir -p zig/x86_64 zig/aarch64

echo "Downloading Zig for x86_64..."
wget -q -O zig-x86_64.tar.xz "$ZIG_URL_X86_64"
tar --no-same-owner -xf zig-x86_64.tar.xz --strip-components=1 -C zig/x86_64
rm zig-x86_64.tar.xz
chmod +x zig/x86_64/zig

echo "Downloading Zig for aarch64..."
wget -q -O zig-aarch64.tar.xz "$ZIG_URL_AARCH64"
tar --no-same-owner -xf zig-aarch64.tar.xz --strip-components=1 -C zig/aarch64
rm zig-aarch64.tar.xz
chmod +x zig/aarch64/zig

# Prefer system Zig for vendoring when it is new enough; otherwise use bundled Zig.
REQUIRED_ZIG_VERSION="0.15.2"
ZIG_BIN="${ZIG_BIN:-}"
HOST_ARCH="$(uname -m)"

case "$HOST_ARCH" in
    x86_64)
        BUNDLED_ZIG="./zig/x86_64/zig"
        ;;
    aarch64|arm64)
        BUNDLED_ZIG="./zig/aarch64/zig"
        ;;
    *)
        BUNDLED_ZIG=""
        ;;
esac

if [ -z "$ZIG_BIN" ]; then
    for candidate in /usr/bin/zig-0.15 /usr/bin/zig zig-0.15 zig15 zig; do
        if command -v "$candidate" >/dev/null 2>&1; then
            candidate_bin=$(command -v "$candidate")
            candidate_ver=$("$candidate_bin" version 2>/dev/null | head -1)
            if [[ "$candidate_ver" =~ ^0\.(1[5-9]|[2-9][0-9]) ]]; then
                ZIG_BIN="$candidate_bin"
                break
            fi
        fi
    done
fi

if [ -z "$ZIG_BIN" ]; then
    if [ -n "$BUNDLED_ZIG" ] && [ -x "$BUNDLED_ZIG" ]; then
        ZIG_BIN="$BUNDLED_ZIG"
    else
        echo "ERROR: Compatible Zig not found. Install Zig ${REQUIRED_ZIG_VERSION}+ or set ZIG_BIN."
        exit 1
    fi
fi

echo "Using Zig binary: $ZIG_BIN ($("$ZIG_BIN" version 2>/dev/null | head -1))"

# Normalize Ghostty themes vendoring details for offline packaging.
echo "Normalizing ghostty-themes vendoring..."
BROKEN_URL="https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/release-20251002-142451-4a5043e/ghostty-themes.tgz"
FIXED_URL="https://deps.files.ghostty.org/ghostty-themes-release-20260216-151611-fc73ce3.tgz"
OLD_HASH="1220c73a50f92bd1aab12c8f8ff96e87e3bb5fbd2a3b9a43d23d450d72db1dc28e99"
NEW_HASH="N-V-__8AABVbAwBwDRyZONfx553tvMW8_A2OKUoLzPUSRiLF"

# Patch build.zig.zon.txt if it contains the broken URL
if [ -f "build.zig.zon.txt" ]; then
    if grep -q "$BROKEN_URL" build.zig.zon.txt; then
        sed -i "s|$BROKEN_URL|$FIXED_URL|g" build.zig.zon.txt
        echo "Patched build.zig.zon.txt"
    fi
fi

# Patch build.zig.zon if it contains the broken URL
if [ -f "build.zig.zon" ]; then
    if grep -q "iTerm2-Color-Schemes" build.zig.zon; then
        # Update URL
        sed -i "s|$BROKEN_URL|$FIXED_URL|g" build.zig.zon
        # Update hash (old format to new format)
        if grep -q "$OLD_HASH" build.zig.zon; then
            sed -i "s|$OLD_HASH|$NEW_HASH|g" build.zig.zon
        fi
        echo "Patched build.zig.zon URL and hash"
    fi
fi

# Download and inject themes tarball into zig-deps (must happen before dependency fetching)
echo "Downloading and injecting themes dependency..."
if [ -f "build.zig.zon" ]; then
    THEME_HASH=$(grep -A2 "iterm2_themes" build.zig.zon | grep hash | sed 's/.*"\(.*\)".*/\1/' | head -1)
    
    if [ -n "$THEME_HASH" ]; then
        echo "Extracted themes hash: $THEME_HASH"
        if wget -q -O ghostty-themes.tgz "$FIXED_URL"; then
            mkdir -p "zig-deps/p/$THEME_HASH"
            tar --no-same-owner -xzf ghostty-themes.tgz -C "zig-deps/p/$THEME_HASH"
            # Keep tarball in source root - Themes are also in zig-deps for --system mode fallback
            echo "Themes dependency injected successfully"
        else
            echo "ERROR: Failed to download themes tarball from $FIXED_URL"
            exit 1
        fi
    else
        echo "WARNING: Could not determine iterm2_themes hash from build.zig.zon"
        echo "Themes may be missing in zig-deps, build may fail"
    fi
fi

# 3. Vendor Zig Dependencies
echo "Vendoring Zig dependencies..."
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-deps"
mkdir -p "$ZIG_GLOBAL_CACHE_DIR"

FETCH_SUCCESS=false

# Use 'zig build --fetch' to fetch all transitive dependencies
echo "Attempting to fetch all dependencies with 'zig build --fetch'..."
if "$ZIG_BIN" build --fetch 2>&1; then
    echo "All dependencies fetched successfully with 'zig build --fetch'"
    FETCH_SUCCESS=true
else
    echo "'zig build --fetch' had some issues, will supplement with other methods"
fi

# Try using official fetch script (if available and build.zig.zon.txt exists)
if [ -f "nix/build-support/fetch-zig-cache.sh" ] && [ -f "build.zig.zon.txt" ]; then
    echo "Supplementing with official fetch-zig-cache.sh script..."
    if bash nix/build-support/fetch-zig-cache.sh; then
        echo "Official fetch-zig-cache.sh completed"
        FETCH_SUCCESS=true
    else
        echo "Official script had issues, continuing..."
    fi
fi

# Manual fetching from dependency list as final supplement
if [ -f "build.zig.zon.txt" ]; then
    echo "Supplementing with manual dependency fetching from build.zig.zon.txt..."
    FETCH_FAILED_COUNT=0
    while IFS= read -r url; do
        [ -z "$url" ] || [[ "$url" =~ ^[[:space:]]*# ]] && continue
        echo "Fetching: $url"
        if ! "$ZIG_BIN" fetch "$url" >/dev/null 2>&1; then
            echo "Failed to fetch (may be optional): $url"
            FETCH_FAILED_COUNT=$((FETCH_FAILED_COUNT + 1))
        fi
    done < "build.zig.zon.txt"
    if [ $FETCH_FAILED_COUNT -gt 0 ]; then
        echo "$FETCH_FAILED_COUNT dependencies failed to fetch (may be optional)"
    fi
    echo "Manual dependency fetch completed"
    FETCH_SUCCESS=true
fi

# Check if we have dependencies now
if [ ! -d "zig-deps/p" ]; then
    echo "ERROR: zig-deps/p directory not created after fetch attempts"
    exit 1
fi

# Count dependencies for verification
DEP_COUNT=$(find zig-deps/p -maxdepth 1 -type d 2>/dev/null | wc -l)
if [ $DEP_COUNT -le 1 ]; then
    echo "ERROR: zig-deps/p/ appears empty (only $((DEP_COUNT - 1)) dependencies found)"
    exit 1
fi
echo "Fetched $((DEP_COUNT - 1)) dependencies to zig-deps/p/"

unset ZIG_GLOBAL_CACHE_DIR

# Create Orig Tarball
cd ..
echo "Creating source tarball..."
rm -rf ghostty-source/.git
rm -rf ghostty-source/.gitignore

mv ghostty-source "ghostty-${VERSION}"

# Tarball naming: ghostty_1.2.3.orig.tar.xz
TARBALL_NAME="${PACKAGE_NAME}_${VERSION}.orig.tar.xz"
tar -cJf "$TARBALL_NAME" "ghostty-${VERSION}"

# Move to Destination
echo "Moving artifacts..."
mv "$TARBALL_NAME" "$PACKAGE_DIR/../"
echo "Created: $PACKAGE_DIR/../$TARBALL_NAME"

# Update changelog if needed
echo "Done. Don't forget to update debian/changelog if this is a new version."
