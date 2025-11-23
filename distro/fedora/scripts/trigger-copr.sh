#!/usr/bin/env bash
# Trigger COPR builds for updated packages
set -euo pipefail

COPR_OWNER="avengemedia"
COPR_PROJECT="danklinux"

if ! command -v copr-cli &> /dev/null; then
    echo "❌ copr-cli not found. Install with: sudo dnf install copr-cli" >&2
    exit 1
fi

if [[ ! -f ~/.config/copr ]]; then
    echo "❌ COPR configuration not found at ~/.config/copr" >&2
    exit 1
fi

trigger_build() {
    local package_name="$1"
    echo "📦 Building $package_name..."
    
    if copr-cli build-package "$COPR_OWNER/$COPR_PROJECT" \
        --name "$package_name" \
        --timeout 7200 \
        --nowait; then
        return 0
    else
        echo "   ❌ Build trigger failed" >&2
        return 1
    fi
}

echo "🔍 Checking for changed spec files..."

if [[ -n "$GITHUB_ACTIONS" ]]; then
    CHANGED_FILES=$(git diff HEAD~1 --name-only 2>/dev/null || echo "")
else
    CHANGED_FILES=$(git diff HEAD~1 --name-only 2>/dev/null || echo "")
fi

# Package build flags
BUILD_QUICKSHELL=false
BUILD_QUICKSHELL_GIT=false
BUILD_DGOP=false
BUILD_CLIPHIST=false
BUILD_MATUGEN=false
BUILD_HYPRPICKER=false
BUILD_BREAKPAD=false
BUILD_GHOSTTY=false
BUILD_MATERIAL_SYMBOLS=false
BUILD_DANKSEARCH=false

# Check which specs changed
if echo "$CHANGED_FILES" | grep -q "quickshell/quickshell.spec"; then
    BUILD_QUICKSHELL=true
fi

if echo "$CHANGED_FILES" | grep -q "quickshell/quickshell-git.spec"; then
    BUILD_QUICKSHELL_GIT=true
fi

if echo "$CHANGED_FILES" | grep -q "dgop/dgop.spec"; then
    BUILD_DGOP=true
fi

if echo "$CHANGED_FILES" | grep -q "cliphist/cliphist.spec"; then
    BUILD_CLIPHIST=true
fi

if echo "$CHANGED_FILES" | grep -q "matugen/matugen.spec"; then
    BUILD_MATUGEN=true
fi

if echo "$CHANGED_FILES" | grep -q "hyprpicker/hyprpicker.spec"; then
    BUILD_HYPRPICKER=true
fi

if echo "$CHANGED_FILES" | grep -q "breakpad/breakpad.spec"; then
    BUILD_BREAKPAD=true
fi

if echo "$CHANGED_FILES" | grep -q "ghostty/ghostty.spec"; then
    BUILD_GHOSTTY=true
fi

if echo "$CHANGED_FILES" | grep -q "fonts/material-symbols-fonts.spec"; then
    BUILD_MATERIAL_SYMBOLS=true
fi

if echo "$CHANGED_FILES" | grep -q "danksearch/danksearch.spec"; then
    BUILD_DANKSEARCH=true
fi

# Note: dms-greeter builds from https://github.com/AvengeMedia/DankMaterialShell
# and is not tracked in this repository

# If no git history, check for uncommitted changes
if [[ -z "$CHANGED_FILES" ]]; then
    echo "ℹ️  No git history found, checking for uncommitted changes..."
    UNCOMMITTED=$(git diff --name-only 2>/dev/null || echo "")

    echo "$UNCOMMITTED" | grep -q "quickshell/quickshell.spec" && BUILD_QUICKSHELL=true
    echo "$UNCOMMITTED" | grep -q "quickshell/quickshell-git.spec" && BUILD_QUICKSHELL_GIT=true
    echo "$UNCOMMITTED" | grep -q "dgop/dgop.spec" && BUILD_DGOP=true
    echo "$UNCOMMITTED" | grep -q "cliphist/cliphist.spec" && BUILD_CLIPHIST=true
    echo "$UNCOMMITTED" | grep -q "matugen/matugen.spec" && BUILD_MATUGEN=true
    echo "$UNCOMMITTED" | grep -q "hyprpicker/hyprpicker.spec" && BUILD_HYPRPICKER=true
    echo "$UNCOMMITTED" | grep -q "breakpad/breakpad.spec" && BUILD_BREAKPAD=true
    echo "$UNCOMMITTED" | grep -q "ghostty/ghostty.spec" && BUILD_GHOSTTY=true
    echo "$UNCOMMITTED" | grep -q "fonts/material-symbols-fonts.spec" && BUILD_MATERIAL_SYMBOLS=true
    echo "$UNCOMMITTED" | grep -q "danksearch/danksearch.spec" && BUILD_DANKSEARCH=true
fi

# Trigger builds
BUILDS_TRIGGERED=0

if [[ "$BUILD_QUICKSHELL" == true ]]; then
    trigger_build "quickshell" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_QUICKSHELL_GIT" == true ]]; then
    trigger_build "quickshell-git" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DGOP" == true ]]; then
    trigger_build "dgop" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_CLIPHIST" == true ]]; then
    trigger_build "cliphist" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_MATUGEN" == true ]]; then
    trigger_build "matugen" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_HYPRPICKER" == true ]]; then
    trigger_build "hyprpicker" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_BREAKPAD" == true ]]; then
    trigger_build "breakpad" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_GHOSTTY" == true ]]; then
    trigger_build "ghostty" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_MATERIAL_SYMBOLS" == true ]]; then
    trigger_build "material-symbols-fonts" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

if [[ "$BUILD_DANKSEARCH" == true ]]; then
    trigger_build "danksearch" && BUILDS_TRIGGERED=$((BUILDS_TRIGGERED + 1))
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $BUILDS_TRIGGERED -gt 0 ]]; then
    echo "✅ Triggered $BUILDS_TRIGGERED COPR build(s)"
    echo "📊 View builds: https://copr.fedorainfracloud.org/coprs/$COPR_OWNER/$COPR_PROJECT/builds/"
else
    echo "ℹ️  No builds triggered (no package changes detected)"
fi
