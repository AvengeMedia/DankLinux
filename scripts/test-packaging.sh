#!/bin/bash
# Manual testing script for danklinux packaging
# Tests OBS (Debian/openSUSE), PPA (Ubuntu), and COPR (Fedora) workflows
# Usage: ./distro/test-packaging.sh [obs|ppa|copr|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISTRO_DIR="$REPO_ROOT/distro"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

TEST_MODE="${1:-all}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "danklinux Packaging Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: OBS Upload (Debian + openSUSE)
if [[ "$TEST_MODE" == "obs" ]] || [[ "$TEST_MODE" == "all" ]]; then
    echo "═══════════════════════════════════════════════════════════════════"
    echo "TEST 1: OBS Upload (Debian + openSUSE)"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    OBS_SCRIPT="$DISTRO_DIR/scripts/obs-upload.sh"
    
    if [[ ! -f "$OBS_SCRIPT" ]]; then
        error "OBS script not found: $OBS_SCRIPT"
        exit 1
    fi
    
    info "OBS script location: $OBS_SCRIPT"
    info "Available packages: cliphist, matugen, niri, niri-git, quickshell-git, danksearch, dgop"
    echo ""
    
    warn "This will upload to OBS (home:AvengeMedia)"
    read -p "Continue with OBS test? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Select package(s) to test:"
        echo "  1. cliphist"
        echo "  2. matugen"
        echo "  3. all packages"
        read -p "Choice [1]: " -n 1 -r PKG_CHOICE
        echo
        echo ""
        
        PKG_CHOICE="${PKG_CHOICE:-1}"
        
        cd "$REPO_ROOT"
        
        case "$PKG_CHOICE" in
            1)
                info "Testing OBS upload for 'cliphist' package..."
                bash "$OBS_SCRIPT" cliphist "Test packaging update"
                ;;
            2)
                info "Testing OBS upload for 'matugen' package..."
                bash "$OBS_SCRIPT" matugen "Test packaging update"
                ;;
            3)
                info "Testing OBS upload for all packages (this will take a while)..."
                bash "$OBS_SCRIPT" all "Test packaging update"
                ;;
            *)
                error "Invalid choice"
                exit 1
                ;;
        esac
        
        echo ""
        success "OBS test completed"
        echo ""
        info "Check build status: https://build.opensuse.org/project/monitor/home:AvengeMedia"
    else
        warn "OBS test skipped"
    fi
    
    echo ""
fi

# Test 2: PPA Upload (Ubuntu)
if [[ "$TEST_MODE" == "ppa" ]] || [[ "$TEST_MODE" == "all" ]]; then
    echo "═══════════════════════════════════════════════════════════════════"
    echo "TEST 2: PPA Upload (Ubuntu)"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    PPA_SCRIPT="$DISTRO_DIR/ubuntu/ppa/create-and-upload.sh"
    
    if [[ ! -f "$PPA_SCRIPT" ]]; then
        error "PPA script not found: $PPA_SCRIPT"
        exit 1
    fi
    
    info "PPA script location: $PPA_SCRIPT"
    info "Available packages: cliphist, matugen, niri, niri-git, quickshell-git"
    info "Ubuntu series: questing (25.10)"
    echo ""
    
    warn "This will upload to Launchpad PPA (ppa:avengemedia/danklinux)"
    read -p "Continue with PPA test? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Select package to test:"
        echo "  1. cliphist"
        echo "  2. matugen"
        echo "  3. niri"
        echo "  4. niri-git"
        echo "  5. quickshell-git"
        read -p "Choice [1]: " -n 1 -r PKG_CHOICE
        echo
        echo ""
        
        PKG_CHOICE="${PKG_CHOICE:-1}"
        
        case "$PKG_CHOICE" in
            1)
                PKG_NAME="cliphist"
                ;;
            2)
                PKG_NAME="matugen"
                ;;
            3)
                PKG_NAME="niri"
                ;;
            4)
                PKG_NAME="niri-git"
                ;;
            5)
                PKG_NAME="quickshell-git"
                ;;
            *)
                error "Invalid choice"
                exit 1
                ;;
        esac
        
        info "Testing PPA upload for '$PKG_NAME' package..."
        echo ""
        
        PKG_DIR="$DISTRO_DIR/ubuntu/$PKG_NAME"
        if [[ ! -d "$PKG_DIR" ]]; then
            error "Package directory not found: $PKG_DIR"
            exit 1
        fi
        
        bash "$PPA_SCRIPT" "$PKG_DIR" danklinux questing
        
        echo ""
        success "PPA test completed"
        echo ""
        info "Check build status: https://launchpad.net/~avengemedia/+archive/ubuntu/danklinux/+packages"
    else
        warn "PPA test skipped"
    fi
    
    echo ""
fi

# Test 3: COPR (Fedora)
if [[ "$TEST_MODE" == "copr" ]] || [[ "$TEST_MODE" == "all" ]]; then
    echo "═══════════════════════════════════════════════════════════════════"
    echo "TEST 3: COPR Version Check & Trigger"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    UPDATE_SCRIPT="$DISTRO_DIR/fedora/scripts/update-packages.sh"
    TRIGGER_SCRIPT="$DISTRO_DIR/fedora/scripts/trigger-copr.sh"
    
    if [[ ! -f "$UPDATE_SCRIPT" ]]; then
        error "COPR update script not found: $UPDATE_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$TRIGGER_SCRIPT" ]]; then
        error "COPR trigger script not found: $TRIGGER_SCRIPT"
        exit 1
    fi
    
    info "COPR scripts location: $DISTRO_DIR/fedora/scripts/"
    info "Available packages: cliphist, matugen, hyprpicker, dgop, quickshell, quickshell-git"
    echo ""
    
    info "Step 1: Checking for version updates..."
    echo ""
    
    cd "$DISTRO_DIR/fedora"
    bash "$UPDATE_SCRIPT"
    
    echo ""
    warn "This will trigger COPR builds (avengemedia/danklinux)"
    read -p "Continue with COPR trigger? [y/N] " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Triggering COPR builds..."
        echo ""
        
        bash "$TRIGGER_SCRIPT"
        
        echo ""
        success "COPR trigger completed"
        echo ""
        info "Check build status: https://copr.fedorainfracloud.org/coprs/avengemedia/danklinux/builds/"
    else
        warn "COPR trigger skipped"
    fi
    
    echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"