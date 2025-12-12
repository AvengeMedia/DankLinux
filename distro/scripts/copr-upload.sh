#!/usr/bin/env bash
# Build SRPM locally and upload to COPR
# Usage: ./copr-upload.sh <package-name>
#   e.g., ./copr-upload.sh quickshell

set -euo pipefail

COPR_OWNER="avengemedia"
COPR_PROJECT="danklinux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
if ! command -v copr-cli &> /dev/null; then
    error "copr-cli not found. Install with: sudo dnf install copr-cli"
    exit 1
fi

if ! command -v rpmbuild &> /dev/null; then
    error "rpmbuild not found. Install with: sudo dnf install rpm-build rpmdevtools"
    exit 1
fi

if [[ ! -f ~/.config/copr ]]; then
    error "COPR configuration not found at ~/.config/copr"
    exit 1
fi

if [[ $# -lt 1 ]]; then
    error "Usage: $0 <package-name>"
    echo ""
    echo "Available packages:"
    echo "  cli11, quickshell, quickshell-git, dgop, cliphist, matugen,"
    echo "  hyprpicker, breakpad, ghostty, danksearch, material-symbols-fonts"
    exit 1
fi

PACKAGE="$1"
SPEC_FILE="$REPO_ROOT/distro/fedora/$PACKAGE/$PACKAGE.spec"

# Handle special cases
if [[ "$PACKAGE" == "material-symbols-fonts" ]]; then
    SPEC_FILE="$REPO_ROOT/distro/fedora/fonts/material-symbols-fonts.spec"
elif [[ "$PACKAGE" == "quickshell-git" ]]; then
    SPEC_FILE="$REPO_ROOT/distro/fedora/quickshell/quickshell-git.spec"
fi

if [[ ! -f "$SPEC_FILE" ]]; then
    error "Spec file not found: $SPEC_FILE"
    exit 1
fi

info "Building SRPM for: $PACKAGE"
info "Spec file: $SPEC_FILE"

BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

SRPM_DIR="$BUILD_DIR/srpms"
mkdir -p "$SRPM_DIR"

# Set up rpmbuild tree
export HOME_RPMBUILD="$BUILD_DIR/rpmbuild"
mkdir -p "$HOME_RPMBUILD"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

info "Building SRPM in: $BUILD_DIR"

# Copy spec file
cp "$SPEC_FILE" "$HOME_RPMBUILD/SPECS/"

cd "$HOME_RPMBUILD/SPECS"
SPEC_NAME=$(basename "$SPEC_FILE")

info "Downloading sources with spectool..."
cd "$HOME_RPMBUILD/SOURCES"

# Use spectool to download sources directly to SOURCES directory
if spectool -g -C "$HOME_RPMBUILD/SOURCES" "$HOME_RPMBUILD/SPECS/$SPEC_NAME" 2>&1 | grep -v "Downloaded:"; then
    success "Sources downloaded with spectool"
else
    warn "spectool failed, trying manual download..."

    # Extract Source0 URL and download manually
    SOURCE_URL=$(grep -oP '^Source0:\s+\K.*' "$HOME_RPMBUILD/SPECS/$SPEC_NAME" | head -1)
    if [[ -n "$SOURCE_URL" ]]; then
        # Expand RPM macros in URL
        URL_BASE=$(grep -oP '^URL:\s+\K.*' "$HOME_RPMBUILD/SPECS/$SPEC_NAME")
        SOURCE_URL=$(echo "$SOURCE_URL" | sed "s|%{url}|$URL_BASE|g")

        if [[ "$SOURCE_URL" == *"/archive/"*".tar.gz" ]]; then
            COMMIT=$(grep -oP '^%global commit\s+\K[a-f0-9]+' "$HOME_RPMBUILD/SPECS/$SPEC_NAME" || echo "")
            if [[ -n "$COMMIT" ]]; then
                SOURCE_URL=$(echo "$SOURCE_URL" | sed "s|%{commit}|$COMMIT|g")
            fi
        fi

        info "Downloading: $SOURCE_URL"
        if wget -q --show-progress "$SOURCE_URL"; then
            success "Source downloaded manually"
        else
            error "Failed to download source"
            exit 1
        fi
    fi
fi

# Build SRPM
info "Building SRPM with rpmbuild..."
cd "$HOME_RPMBUILD/SPECS"

if rpmbuild -bs \
    --define "_topdir $HOME_RPMBUILD" \
    --define "_sourcedir $HOME_RPMBUILD/SOURCES" \
    --define "_srcrpmdir $SRPM_DIR" \
    "$SPEC_NAME"; then
    success "SRPM built successfully"
else
    error "SRPM build failed"
    exit 1
fi

SRPM_FILE=$(find "$SRPM_DIR" -name "*.src.rpm" | head -1)

if [[ ! -f "$SRPM_FILE" ]]; then
    error "SRPM file not found in $SRPM_DIR"
    exit 1
fi

info "SRPM: $SRPM_FILE"

# Upload to COPR
info "Uploading SRPM to COPR..."
echo ""

if copr-cli build "$COPR_OWNER/$COPR_PROJECT" "$SRPM_FILE" --nowait; then
    success "Build submitted to COPR!"
    echo ""
    info "📊 View builds: https://copr.fedorainfracloud.org/coprs/$COPR_OWNER/$COPR_PROJECT/builds/"
else
    error "COPR upload failed"
    exit 1
fi
