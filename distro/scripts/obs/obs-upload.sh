#!/bin/bash
# OBS Upload Coordinator
# Handles uploading build artifacts to OpenBuildService

set -euo pipefail

# Get script directory and source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=./lib/package-config.sh
source "$SCRIPT_DIR/lib/package-config.sh"

# Initialize
init_common

# OBS Configuration
OBS_PROJECT="${OBS_PROJECT:-home:AvengeMedia:danklinux}"
OBS_CACHE_DIR="$HOME/.cache/osc-checkouts"

# Usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] PACKAGE ARTIFACTS_DIR

Upload build artifacts to OBS.

ARGUMENTS:
  PACKAGE         Package name (e.g., niri-git)
  ARTIFACTS_DIR   Directory containing build artifacts

OPTIONS:
  --distro=DIST   Target distro: debian, opensuse, or both (default: both)
  --message=MSG   Commit message (default: "Automated update")
  --verbose       Enable verbose output
  -h, --help      Show this help message

EXAMPLES:
  $(basename "$0") niri-git /tmp/build/niri-git
  $(basename "$0") --distro=debian ghostty /tmp/build/ghostty
  $(basename "$0") --message="Fix build" cliphist /tmp/build/cliphist

EOF
    exit 0
}

# Parse arguments
TARGET_DISTRO="both"
COMMIT_MESSAGE="Automated update from OBS automation"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --distro=*)
            TARGET_DISTRO="${1#*=}"
            shift
            ;;
        --message=*)
            COMMIT_MESSAGE="${1#*=}"
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
ARTIFACTS_DIR="${2:-}"

if [[ -z "$PACKAGE" || -z "$ARTIFACTS_DIR" ]]; then
    log_error "Missing required arguments"
    usage
fi

# Validate package exists
if ! validate_package "$PACKAGE"; then
    log_error "Package not found: $PACKAGE"
    exit $ERR_CONFIG
fi

# Validate artifacts directory
if [[ ! -d "$ARTIFACTS_DIR" ]]; then
    log_error "Artifacts directory not found: $ARTIFACTS_DIR"
    exit $ERR_CONFIG
fi

# Check if osc is available
require_command osc "osc (OpenBuildService command line client)"

log_info "Uploading package: $PACKAGE"
log_info "Artifacts: $ARTIFACTS_DIR"
log_info "Target distro: $TARGET_DISTRO"
log_info "OBS project: $OBS_PROJECT"

# Ensure OBS cache directory exists
mkdir -p "$OBS_CACHE_DIR"

# Package checkout directory
PKG_DIR="$OBS_CACHE_DIR/$OBS_PROJECT/$PACKAGE"

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Checking out package from OBS"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Checkout or update package
cd "$OBS_CACHE_DIR"

if [[ -d "$PKG_DIR" ]]; then
    log_info "Package already checked out, updating..."
    cd "$PKG_DIR"

    # Update with conflict resolution
    if ! osc up 2>&1 | tee /tmp/osc-up.log; then
        log_warn "osc up encountered issues, checking for conflicts..."

        # Check for conflicts
        if grep -q "conflicts" /tmp/osc-up.log; then
            log_warn "Conflicts detected, resolving..."

            # Remove conflicted files and try again
            osc resolved * 2>/dev/null || true
            osc revert * 2>/dev/null || true

            if ! osc up; then
                log_error "Failed to resolve conflicts, doing fresh checkout..."
                cd "$OBS_CACHE_DIR"
                rm -rf "$PKG_DIR"

                if ! osc co "$OBS_PROJECT" "$PACKAGE"; then
                    log_error "Package does not exist on OBS: $PACKAGE"
                    log_error "Please create the package first with: osc mkpac $PACKAGE"
                    exit $ERR_UPLOAD_FAILURE
                fi

                cd "$PKG_DIR"
            fi
        fi
    fi
else
    log_info "Checking out package for the first time..."

    osc co "$OBS_PROJECT" "$PACKAGE" 2>&1 || true
    
    # Check if checkout actually succeeded by checking if directory exists
    if [[ ! -d "$PKG_DIR" ]]; then
        log_warn "Package does not exist on OBS, will be created"

        # Create package directory structure
        mkdir -p "$OBS_CACHE_DIR/$OBS_PROJECT"
        cd "$OBS_CACHE_DIR/$OBS_PROJECT"

        # Initialize OBS project if needed
        if [[ ! -d ".osc" ]]; then
            osc co "$OBS_PROJECT" 2>/dev/null || {
                log_error "Failed to checkout OBS project: $OBS_PROJECT"
                log_error "Please ensure the project exists and you have access"
                exit $ERR_UPLOAD_FAILURE
            }
        fi

        cd "$OBS_PROJECT"

        # Create package
        if ! osc mkpac "$PACKAGE" 2>&1; then
            log_error "Failed to create package on OBS"
            exit $ERR_UPLOAD_FAILURE
        fi

        cd "$PACKAGE"
    else
        cd "$PKG_DIR"
    fi
fi

log_success "Package checked out: $PKG_DIR"

# Clean up old artifacts (remove from both filesystem and OBS)
log_info "Cleaning up old artifacts..."

# Temporarily disable failglob for cleanup
shopt -u failglob 2>/dev/null || true

# Remove all old build artifacts from OBS tracking and filesystem
for pattern in "*.tar" "*.tar.*" "*.dsc" "*.spec" "_service"; do
    for file in $pattern; do
        if [[ -f "$file" ]]; then
            log_debug "Removing old file: $file"
            osc rm "$file" 2>/dev/null || true
            rm -f "$file"
        fi
    done
done

# Determine which artifacts to upload
UPLOAD_DEBIAN=false
UPLOAD_OPENSUSE=false

case "$TARGET_DISTRO" in
    both)
        if package_supports_distro "$PACKAGE" "debian"; then
            UPLOAD_DEBIAN=true
        fi
        if package_supports_distro "$PACKAGE" "opensuse"; then
            UPLOAD_OPENSUSE=true
        fi
        ;;
    debian)
        if package_supports_distro "$PACKAGE" "debian"; then
            UPLOAD_DEBIAN=true
        else
            log_error "$PACKAGE does not support Debian"
            exit $ERR_CONFIG
        fi
        ;;
    opensuse)
        if package_supports_distro "$PACKAGE" "opensuse"; then
            UPLOAD_OPENSUSE=true
        else
            log_error "$PACKAGE does not support OpenSUSE"
            exit $ERR_CONFIG
        fi
        ;;
    *)
        log_error "Unknown distro: $TARGET_DISTRO"
        exit $ERR_CONFIG
        ;;
esac

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Copying build artifacts"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Copy Debian artifacts
if [[ "$UPLOAD_DEBIAN" == "true" ]]; then
    log_info "Copying Debian artifacts..."

    # Copy .dsc, .tar.*, .debian.tar.*, _service
    find "$ARTIFACTS_DIR" -maxdepth 1 -type f \( -name "*.dsc" -o -name "*.tar.*" -o -name "*.debian.tar.*" -o -name "_service" \) -exec cp -v {} . \;

    log_success "Debian artifacts copied"
fi

# Copy OpenSUSE artifacts
if [[ "$UPLOAD_OPENSUSE" == "true" ]]; then
    log_info "Copying OpenSUSE artifacts..."

    # Copy .spec, source tarballs (compressed and uncompressed), binary .gz files, _service
    find "$ARTIFACTS_DIR" -maxdepth 1 -type f \( -name "*.spec" -o -name "*.tar" -o -name "*.tar.*" -o -name "*.gz" -o -name "_service" \) -exec cp -v {} . \;

    log_success "OpenSUSE artifacts copied"
fi

# Add new files
log_info "Adding files to OBS..."
osc addremove

# Check status
log_info "Checking status..."
osc status

# Commit changes
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Committing to OBS"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Commit message: $COMMIT_MESSAGE"

if ! timeout 1800 osc commit -m "$COMMIT_MESSAGE" 2>&1 | tee /tmp/osc-commit.log; then
    log_error "Failed to commit to OBS"

    # Check for common errors
    if grep -q "no changes" /tmp/osc-commit.log; then
        log_warn "No changes to commit (files already up to date)"
        exit 0
    elif grep -q "conflict" /tmp/osc-commit.log; then
        log_error "Conflicts detected. Please resolve manually:"
        log_error "  cd $PKG_DIR"
        log_error "  osc resolved <files>"
        log_error "  osc commit"
        exit $ERR_UPLOAD_FAILURE
    else
        log_error "See commit log: /tmp/osc-commit.log"
        exit $ERR_UPLOAD_FAILURE
    fi
fi

log_success "Upload completed successfully!"

# Show build URL
BUILD_URL="https://build.opensuse.org/package/show/$OBS_PROJECT/$PACKAGE"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Build Status"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "View build status: $BUILD_URL"
log_info ""
log_info "Check build results with:"
log_info "  osc results $OBS_PROJECT $PACKAGE"
log_info ""
log_info "Monitor build logs with:"
log_info "  osc buildlog $OBS_PROJECT $PACKAGE <repo> <arch>"

exit 0
