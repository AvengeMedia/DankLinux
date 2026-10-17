#!/usr/bin/env bash
# Trigger COPR builds for updated packages
set -euo pipefail

COPR_OWNER="avengemedia"
COPR_PROJECT="danklinux"
# The SCM default source method of the existing packages
COPR_CLONE_URL="https://github.com/AvengeMedia/danklinux.git"

if ! command -v copr-cli &> /dev/null; then
    echo "❌ copr-cli not found. Install with: sudo dnf install copr-cli" >&2
    exit 1
fi

if [[ ! -f ~/.config/copr ]]; then
    echo "❌ COPR configuration not found at ~/.config/copr" >&2
    exit 1
fi

# Chroots a package must never build in: Fedora ships these itself, and EPEL zig is x86_64 only
chroot_denylist() {
    case "$1" in
        greetd|gtk4-layer-shell|cava|alacritty|xwayland-satellite) echo "fedora-*" ;;
        ghostty) echo "epel-10-aarch64,centos-stream-10-aarch64" ;;
    esac
}

# Ensure the COPR package has a default SCM source method configured.
# build-package rebuilds rely on this; newly added packages may lack it,
# which fails with "doesn't have the default source method set".
# edit-package-scm updates an existing package; if it doesn't exist yet,
# fall back to add-package-scm. Idempotent and safe to re-run.
ensure_scm() {
    local package_name="$1"
    local spec_file="$2"
    local subdir spec denylist
    local scm_args=()

    subdir="$(dirname "$spec_file")"
    spec="$(basename "$spec_file")"
    denylist="$(chroot_denylist "$package_name")"

    scm_args=(
        --name "$package_name"
        --clone-url "$COPR_CLONE_URL"
        --subdir "$subdir"
        --spec "$spec"
        --type git
        --method rpkg
    )
    if [[ -n "$denylist" ]]; then
        scm_args+=(--chroot-denylist "$denylist")
    fi

    copr-cli edit-package-scm "$COPR_OWNER/$COPR_PROJECT" "${scm_args[@]}" \
    || copr-cli add-package-scm "$COPR_OWNER/$COPR_PROJECT" "${scm_args[@]}"
}

# COPR_CHROOTS: optional space-separated chroot list, limits every build in this run
CHROOT_ARGS=()
for chroot in ${COPR_CHROOTS:-}; do
    CHROOT_ARGS+=(-r "$chroot")
done

trigger_build() {
    local package_name="$1"
    local spec_file="$2"
    
    echo "📦 Building $package_name... ${COPR_CHROOTS:+(chroots: $COPR_CHROOTS)}"

    if ! ensure_scm "$package_name" "$spec_file"; then
        echo "   ❌ Failed to configure SCM default source" >&2
        return 1
    fi

    if copr-cli build-package "$COPR_OWNER/$COPR_PROJECT" \
        --name "$package_name" \
        --timeout 7200 \
        --nowait "${CHROOT_ARGS[@]}"; then
        return 0
    else
        echo "   ❌ Build trigger failed" >&2
        return 1
    fi
}

echo "🔍 Checking for changed spec files..."

# If MANUAL_PACKAGE is set, only build that package
if [[ -n "${MANUAL_PACKAGE:-}" ]]; then
    echo "📦 Manual package specified: $MANUAL_PACKAGE"
    FORCE_PACKAGE="$MANUAL_PACKAGE"
else
    FORCE_PACKAGE=""
fi

# COPR_SKIP_DIFF=true: HEAD is not a commit made by this run, so its diff is stale
# COPR_DIFF_BASE: commit the run started from, so pushed specs survive an auto-update commit on top
DIFF_BASE="${COPR_DIFF_BASE:-HEAD~1}"
git cat-file -e "$DIFF_BASE^{commit}" 2>/dev/null || DIFF_BASE=HEAD~1
if [[ "${COPR_SKIP_DIFF:-false}" == "true" ]]; then
    echo "ℹ️  Skipping $DIFF_BASE diff (no new commit in this run)"
    CHANGED_FILES=""
else
    echo "ℹ️  Comparing $DIFF_BASE..HEAD"
    CHANGED_FILES=$(git diff "$DIFF_BASE" HEAD --name-only 2>/dev/null || echo "")
fi

# Package build flags
BUILD_QUICKSHELL=false
BUILD_QUICKSHELL_GIT=false
BUILD_DGOP=false
BUILD_CLIPHIST=false
BUILD_MATUGEN=false
BUILD_BREAKPAD=false
BUILD_GHOSTTY=false
BUILD_MATERIAL_SYMBOLS=false
BUILD_DANKSEARCH=false
BUILD_DANKCALENDAR=false
BUILD_DANKCALENDAR_GIT=false
BUILD_CLI11=false
BUILD_QT6CT_KDE=false
BUILD_GREETD=false
BUILD_GTK4_LAYER_SHELL=false
BUILD_CAVA=false
BUILD_ALACRITTY=false
BUILD_XWAYLAND_SATELLITE=false

# Handle "all" as a special force-all-packages shortcut
if [[ "${FORCE_PACKAGE:-}" == "all" ]]; then
    echo "📦 Force-all: enabling builds for every package"
    BUILD_QUICKSHELL=true
    BUILD_QUICKSHELL_GIT=true
    BUILD_DGOP=true
    BUILD_CLIPHIST=true
    BUILD_MATUGEN=true
    BUILD_BREAKPAD=true
    BUILD_GHOSTTY=true
    BUILD_MATERIAL_SYMBOLS=true
    BUILD_DANKSEARCH=true
    BUILD_DANKCALENDAR=true
    BUILD_DANKCALENDAR_GIT=true
    BUILD_CLI11=true
    BUILD_QT6CT_KDE=true
    BUILD_GREETD=true
    BUILD_GTK4_LAYER_SHELL=true
    BUILD_CAVA=true
    BUILD_ALACRITTY=true
    BUILD_XWAYLAND_SATELLITE=true
fi

# Check which specs changed (paths relative to repo root)
if echo "$CHANGED_FILES" | grep -q "distro/fedora/quickshell/quickshell.spec"; then
    BUILD_QUICKSHELL=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/quickshell/quickshell-git.spec"; then
    BUILD_QUICKSHELL_GIT=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/dgop/dgop.spec"; then
    BUILD_DGOP=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/cliphist/cliphist.spec"; then
    BUILD_CLIPHIST=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/matugen/matugen.spec"; then
    BUILD_MATUGEN=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/breakpad/breakpad.spec"; then
    BUILD_BREAKPAD=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/ghostty/ghostty.spec"; then
    BUILD_GHOSTTY=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/fonts/material-symbols-fonts.spec"; then
    BUILD_MATERIAL_SYMBOLS=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/danksearch/danksearch.spec"; then
    BUILD_DANKSEARCH=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/dankcalendar/dankcalendar.spec"; then
    BUILD_DANKCALENDAR=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/dankcalendar/dankcalendar-git.spec"; then
    BUILD_DANKCALENDAR=true
    BUILD_DANKCALENDAR_GIT=true
fi

# New CLI11 package
if echo "$CHANGED_FILES" | grep -q "distro/fedora/cli11/cli11.spec"; then
    BUILD_CLI11=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/qt6ct-kde/qt6ct-kde.spec"; then
    BUILD_QT6CT_KDE=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/greetd/greetd.spec"; then
    BUILD_GREETD=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/gtk4-layer-shell/gtk4-layer-shell.spec"; then
    BUILD_GTK4_LAYER_SHELL=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/cava/cava.spec"; then
    BUILD_CAVA=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/alacritty/alacritty.spec"; then
    BUILD_ALACRITTY=true
fi

if echo "$CHANGED_FILES" | grep -q "distro/fedora/xwayland-satellite/xwayland-satellite.spec"; then
    BUILD_XWAYLAND_SATELLITE=true
fi

# Note: dms-greeter / dms-greeter-git build from https://github.com/AvengeMedia/dank-greeter
# and are published into avengemedia/danklinux by that repo's CI

# If no git history, check for uncommitted changes
if [[ -z "$CHANGED_FILES" ]]; then
    echo "ℹ️  No git history found, checking for uncommitted changes..."
    UNCOMMITTED=$(git diff --name-only 2>/dev/null || echo "")

    echo "$UNCOMMITTED" | grep -q "distro/fedora/quickshell/quickshell.spec" && BUILD_QUICKSHELL=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/quickshell/quickshell-git.spec" && BUILD_QUICKSHELL_GIT=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/dgop/dgop.spec" && BUILD_DGOP=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/cliphist/cliphist.spec" && BUILD_CLIPHIST=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/matugen/matugen.spec" && BUILD_MATUGEN=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/breakpad/breakpad.spec" && BUILD_BREAKPAD=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/ghostty/ghostty.spec" && BUILD_GHOSTTY=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/fonts/material-symbols-fonts.spec" && BUILD_MATERIAL_SYMBOLS=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/danksearch/danksearch.spec" && BUILD_DANKSEARCH=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/dankcalendar/dankcalendar.spec" && BUILD_DANKCALENDAR=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/dankcalendar/dankcalendar-git.spec" && BUILD_DANKCALENDAR_GIT=true

    # New CLI11 package
    echo "$UNCOMMITTED" | grep -q "distro/fedora/cli11/cli11.spec" && BUILD_CLI11=true

    echo "$UNCOMMITTED" | grep -q "distro/fedora/qt6ct-kde/qt6ct-kde.spec" && BUILD_QT6CT_KDE=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/greetd/greetd.spec" && BUILD_GREETD=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/gtk4-layer-shell/gtk4-layer-shell.spec" && BUILD_GTK4_LAYER_SHELL=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/cava/cava.spec" && BUILD_CAVA=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/alacritty/alacritty.spec" && BUILD_ALACRITTY=true
    echo "$UNCOMMITTED" | grep -q "distro/fedora/xwayland-satellite/xwayland-satellite.spec" && BUILD_XWAYLAND_SATELLITE=true
fi

# Trigger builds
BUILDS_TRIGGERED=0

if [[ "$BUILD_QUICKSHELL" == true ]] || [[ "$FORCE_PACKAGE" == "quickshell" ]]; then
    trigger_build "quickshell" "distro/fedora/quickshell/quickshell.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_QUICKSHELL_GIT" == true ]] || [[ "$FORCE_PACKAGE" == "quickshell-git" ]]; then
    trigger_build "quickshell-git" "distro/fedora/quickshell/quickshell-git.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DGOP" == true ]] || [[ "$FORCE_PACKAGE" == "dgop" ]]; then
    trigger_build "dgop" "distro/fedora/dgop/dgop.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_CLIPHIST" == true ]] || [[ "$FORCE_PACKAGE" == "cliphist" ]]; then
    trigger_build "cliphist" "distro/fedora/cliphist/cliphist.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_MATUGEN" == true ]] || [[ "$FORCE_PACKAGE" == "matugen" ]]; then
    trigger_build "matugen" "distro/fedora/matugen/matugen.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_BREAKPAD" == true ]] || [[ "$FORCE_PACKAGE" == "breakpad" ]]; then
    trigger_build "breakpad" "distro/fedora/breakpad/breakpad.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_GHOSTTY" == true ]] || [[ "$FORCE_PACKAGE" == "ghostty" ]]; then
    trigger_build "ghostty" "distro/fedora/ghostty/ghostty.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_MATERIAL_SYMBOLS" == true ]] || [[ "$FORCE_PACKAGE" == "material-symbols-fonts" ]]; then
    trigger_build "material-symbols-fonts" "distro/fedora/fonts/material-symbols-fonts.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DANKSEARCH" == true ]] || [[ "$FORCE_PACKAGE" == "danksearch" ]]; then
    trigger_build "danksearch" "distro/fedora/danksearch/danksearch.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DANKCALENDAR" == true ]] || [[ "$FORCE_PACKAGE" == "dankcalendar" ]]; then
    trigger_build "dankcalendar" "distro/fedora/dankcalendar/dankcalendar.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DANKCALENDAR_GIT" == true ]] || [[ "$FORCE_PACKAGE" == "dankcalendar-git" ]]; then
    trigger_build "dankcalendar-git" "distro/fedora/dankcalendar/dankcalendar-git.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_CLI11" == true ]] || [[ "$FORCE_PACKAGE" == "cli11" ]]; then
    trigger_build "cli11" "distro/fedora/cli11/cli11.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_QT6CT_KDE" == true ]] || [[ "$FORCE_PACKAGE" == "qt6ct-kde" ]]; then
    trigger_build "qt6ct-kde" "distro/fedora/qt6ct-kde/qt6ct-kde.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_GREETD" == true ]] || [[ "$FORCE_PACKAGE" == "greetd" ]]; then
    trigger_build "greetd" "distro/fedora/greetd/greetd.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_GTK4_LAYER_SHELL" == true ]] || [[ "$FORCE_PACKAGE" == "gtk4-layer-shell" ]]; then
    trigger_build "gtk4-layer-shell" "distro/fedora/gtk4-layer-shell/gtk4-layer-shell.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_CAVA" == true ]] || [[ "$FORCE_PACKAGE" == "cava" ]]; then
    trigger_build "cava" "distro/fedora/cava/cava.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_ALACRITTY" == true ]] || [[ "$FORCE_PACKAGE" == "alacritty" ]]; then
    trigger_build "alacritty" "distro/fedora/alacritty/alacritty.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_XWAYLAND_SATELLITE" == true ]] || [[ "$FORCE_PACKAGE" == "xwayland-satellite" ]]; then
    trigger_build "xwayland-satellite" "distro/fedora/xwayland-satellite/xwayland-satellite.spec" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $BUILDS_TRIGGERED -gt 0 ]]; then
    echo "✅ Triggered $BUILDS_TRIGGERED COPR build(s)"
    echo "📊 View builds: https://copr.fedorainfracloud.org/coprs/$COPR_OWNER/$COPR_PROJECT/builds/"
else
    echo "ℹ️  No builds triggered (no package changes detected)"
fi

# Fail visibly if packages were expected to build but none were triggered.
# This surfaces copr-cli errors, SCM misconfiguration, or auth failures
# instead of letting the job exit green while silently doing nothing.
if [[ $BUILDS_TRIGGERED -eq 0 ]] && { [[ -n "$CHANGED_FILES" ]] || [[ -n "${FORCE_PACKAGE:-}" ]]; }; then
    echo ""
    echo "❌ Builds were expected (changed files or forced package detected) but none were triggered."
    echo "   Check copr-cli output above for errors, and verify COPR SCM configuration."
    exit 1
fi
