#!/usr/bin/env bash
# Auto-update package specs with latest versions from GitHub
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT/distro/fedora"

# Track if any packages were updated
UPDATED=0
UPDATED_PACKAGES=()

echo "🔍 Checking for package updates..."

echo ""
echo "📦 Checking quickshell (stable)..."

SPEC_FILE="quickshell/quickshell.spec"
UPSTREAM_REPO="quickshell-mirror/quickshell"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^%global tag\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"  # Remove 'v' prefix

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^%global tag\s\+.*/%global tag         $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("quickshell: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# QUICKSHELL-GIT (Latest Commit)
# ============================================================================
echo ""
echo "📦 Checking quickshell-git (development)..."

SPEC_FILE="quickshell/quickshell-git.spec"

# Get current commit from spec
CURRENT_COMMIT=$(grep -oP '^%global commit\s+\K[a-f0-9]+' "$SPEC_FILE" || echo "unknown")
CURRENT_SNAPDATE=$(grep -oP '^%global snapdate\s+\K[0-9]+' "$SPEC_FILE" || echo "unknown")
echo "   Current commit: ${CURRENT_COMMIT:0:7} (date: $CURRENT_SNAPDATE)"

# Fetch latest commit info
COMMIT_INFO=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "commit")
IFS='|' read -r LATEST_COMMIT LATEST_SHORT_COMMIT LATEST_SNAPDATE <<< "$COMMIT_INFO"

if [[ -n "$LATEST_COMMIT" ]]; then
    echo "   Latest commit:  ${LATEST_SHORT_COMMIT} (date: $LATEST_SNAPDATE)"

    if [[ "$CURRENT_COMMIT" != "$LATEST_COMMIT" ]]; then
        echo "   ✨ Update available: ${CURRENT_COMMIT:0:7} → ${LATEST_SHORT_COMMIT}"

        # Get commit count by cloning shallow repo
        TMP_DIR=$(mktemp -d)
        git clone --bare "https://github.com/${UPSTREAM_REPO}.git" "$TMP_DIR" &>/dev/null
        COMMIT_COUNT=$(git -C "$TMP_DIR" rev-list --count HEAD)
        rm -rf "$TMP_DIR"

        echo "   Commit count: $COMMIT_COUNT"

        # Update the spec file
        sed -i "s/^%global commit\s\+.*/%global commit      $LATEST_COMMIT/" "$SPEC_FILE"
        sed -i "s/^%global commits\s\+.*/%global commits     $COMMIT_COUNT/" "$SPEC_FILE"
        sed -i "s/^%global snapdate\s\+.*/%global snapdate    $LATEST_SNAPDATE/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("quickshell-git: ${CURRENT_COMMIT:0:7} → ${LATEST_SHORT_COMMIT}")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest commit"
fi

# ============================================================================
# DGOP (Your package!)
# ============================================================================
echo ""
echo "📦 Checking dgop..."

SPEC_FILE="dgop/dgop.spec"
UPSTREAM_REPO="AvengeMedia/dgop"

# Get current version from simplified spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("dgop: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# CLIPHIST
# ============================================================================
echo ""
echo "📦 Checking cliphist..."

SPEC_FILE="cliphist/cliphist.spec"
UPSTREAM_REPO="sentriz/cliphist"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("cliphist: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# MATUGEN
# ============================================================================
echo ""
echo "📦 Checking matugen..."

SPEC_FILE="matugen/matugen.spec"
UPSTREAM_REPO="InioX/matugen"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("matugen: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# HYPRPICKER
# ============================================================================
echo ""
echo "📦 Checking hyprpicker..."

SPEC_FILE="hyprpicker/hyprpicker.spec"
UPSTREAM_REPO="hyprwm/hyprpicker"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("hyprpicker: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# BREAKPAD (uses date-based versioning)
# ============================================================================
echo ""
echo "📦 Checking breakpad..."

SPEC_FILE="breakpad/breakpad.spec"
UPSTREAM_REPO="chromium/breakpad/breakpad"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Note: Breakpad uses commit-based releases, checking latest tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release" 2>/dev/null || echo "")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:            $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("breakpad: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ℹ️  Breakpad uses manual versioning (chromium snapshots)"
    echo "   Current version: $CURRENT_VERSION"
fi

# ============================================================================
# GHOSTTY
# ============================================================================
echo ""
echo "📦 Checking ghostty..."

SPEC_FILE="ghostty/ghostty.spec"
UPSTREAM_REPO="ghostty-org/ghostty"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("ghostty: $CURRENT_VERSION → $LATEST_VERSION")
    else
        echo "   ✓ Already up to date"
    fi
else
    echo "   ⚠ Could not fetch latest version"
fi

# ============================================================================
# DMS-GREETER (Managed separately)
# ============================================================================
echo ""
echo "📦 Checking dms-greeter..."
echo "   ℹ️  Builds directly from: https://github.com/AvengeMedia/DankMaterialShell"
echo "   Not tracked in dms_copr repo - managed in separate DankMaterialShell repo"
echo "   Skipping automatic updates (separate repository)"

# ============================================================================
# MATERIAL SYMBOLS FONTS (rarely updates)
# ============================================================================
echo ""
echo "📦 Checking material-symbols-fonts..."
echo "   ℹ️  Font file from google/material-design-icons (no version tags)"
echo "   Current: 1.0 (manually versioned)"
echo "   Skipping automatic updates for font file"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $UPDATED -gt 0 ]]; then
    echo "✅ Updated $UPDATED package(s):"
    for pkg in "${UPDATED_PACKAGES[@]}"; do
        echo "   • $pkg"
    done
    echo ""
    echo "📝 Changes staged for commit"
    exit 0
else
    echo "✓ All packages are up to date"
    exit 0
fi
