#!/usr/bin/env bash
# Auto-update package specs with latest versions from GitHub
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/distro/fedora"

# Track if any packages were updated
UPDATED=0
UPDATED_PACKAGES=()

echo "🔍 Checking for package updates..."

echo ""
echo "📦 Checking quickshell (stable)..."

SPEC_FILE="quickshell/quickshell.spec"
UPSTREAM_REPO="quickshell-mirror/quickshell"

# Snapshot from snapshots.yaml (commit-based stable)
USE_SNAPSHOT=false
if [ -f "$REPO_ROOT/distro/snapshots.yaml" ]; then
    if command -v yq &> /dev/null; then
        SNAPSHOT_ENABLED=$(yq eval '.quickshell.enabled' "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "false")
        if [ "$SNAPSHOT_ENABLED" = "true" ]; then
            SNAPSHOT_BASE=$(yq eval '.quickshell.base_version' "$REPO_ROOT/distro/snapshots.yaml")

            LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
            LATEST_VERSION="${LATEST_TAG#v}"

            if [[ -n "$LATEST_VERSION" ]] && [[ "$(printf '%s\n' "$LATEST_VERSION" "$SNAPSHOT_BASE" | sort -V | tail -1)" != "$SNAPSHOT_BASE" ]]; then
                echo "   📌 Snapshot override: new stable $LATEST_VERSION (newer than base $SNAPSHOT_BASE)"
                USE_SNAPSHOT=false
            else
                echo "   📌 Using snapshot commit (no stable release newer than $SNAPSHOT_BASE)"
                USE_SNAPSHOT=true
                PINNED_COMMIT=$(yq eval '.quickshell.commit' "$REPO_ROOT/distro/snapshots.yaml")
                PINNED_COUNT=$(yq eval '.quickshell.commit_count' "$REPO_ROOT/distro/snapshots.yaml")
                PINNED_DATE=$(yq eval '.quickshell.snap_date' "$REPO_ROOT/distro/snapshots.yaml")
            fi
        fi
    fi
fi

if [ "$USE_SNAPSHOT" = "true" ]; then
    CURRENT_COMMIT=$(grep -oP '^%global commit\s+\K[a-f0-9]+' "$SPEC_FILE" 2>/dev/null || echo "")

    if [[ "$CURRENT_COMMIT" != "$PINNED_COMMIT" ]]; then
        echo "   ✨ Updating to snapshot commit: ${PINNED_COMMIT:0:7}"

        if grep -q '^%global commit' "$SPEC_FILE"; then
            sed -i "s/^%global commit\s\+.*/%global commit      $PINNED_COMMIT/" "$SPEC_FILE"
            sed -i "s/^%global commits\s\+.*/%global commits     $PINNED_COUNT/" "$SPEC_FILE"
            sed -i "s/^%global snapdate\s\+.*/%global snapdate    $PINNED_DATE/" "$SPEC_FILE"
        else
            sed -i "/^%global tag/a %global commit      $PINNED_COMMIT\n%global commits     $PINNED_COUNT\n%global snapdate    $PINNED_DATE" "$SPEC_FILE"

            sed -i "s/^Version:.*/Version:            %{tag}.1+snapshot%{commits}.%(c=%{commit}; echo \${c:0:7})/" "$SPEC_FILE"

            sed -i "s|^Source0:.*|Source0:            %{url}/archive/%{commit}/quickshell-%{commit}.tar.gz|" "$SPEC_FILE"

            sed -i "s/%autosetup -n quickshell-.*/%autosetup -n quickshell-%{commit} -p1/" "$SPEC_FILE"

            if ! grep -q "DGIT_REVISION" "$SPEC_FILE"; then
                sed -i '/-DDISTRIBUTOR=/a\        -DGIT_REVISION=%{commit} \\' "$SPEC_FILE"
            fi
        fi

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("quickshell: snapshot ${PINNED_COMMIT:0:7}")
    else
        echo "   ✓ Already at snapshot commit"
    fi
else
    # Normal release-based update
    # Get current version from spec
    CURRENT_VERSION=$(grep -oP '^%global tag\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
    echo "   Current: $CURRENT_VERSION"

    # Fetch latest release tag
    LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
    LATEST_VERSION="${LATEST_TAG#v}"  # Remove 'v' prefix

    if [[ -n "$LATEST_VERSION" ]]; then
        echo "   Latest:  $LATEST_VERSION"

        if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
            echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

            if grep -q '^%global commit' "$SPEC_FILE"; then
                echo "   🔄 Transitioning from snapshot to stable release"

                # Remove snapshot commit globals
                sed -i '/^%global commit/d' "$SPEC_FILE"
                sed -i '/^%global commits/d' "$SPEC_FILE"
                sed -i '/^%global snapdate/d' "$SPEC_FILE"

                # Update Version line back to simple tag format
                sed -i "s/^Version:.*/Version:            %{tag}/" "$SPEC_FILE"

                # Update Source0 to use tag instead of commit
                sed -i "s|^Source0:.*|Source0:            %{url}/archive/v%{tag}/quickshell-%{tag}.tar.gz|" "$SPEC_FILE"

                # Update %autosetup to use tag directory
                sed -i "s/%autosetup -n quickshell-.*/%autosetup -n quickshell-%{tag} -p1/" "$SPEC_FILE"

                # Remove -DGIT_REVISION line
                sed -i '/-DGIT_REVISION/d' "$SPEC_FILE"
            fi

            # Update the tag version
            sed -i "s/^%global tag\s\+.*/%global tag         $LATEST_VERSION/" "$SPEC_FILE"

            UPDATED=$((UPDATED + 1))
            UPDATED_PACKAGES+=("quickshell: $CURRENT_VERSION → $LATEST_VERSION")
        else
            echo "   ✓ Already up to date"
        fi
    else
        echo "   ⚠ Could not fetch latest version"
    fi
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
COMMIT_INFO=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "commit")
IFS='|' read -r LATEST_COMMIT LATEST_SHORT_COMMIT LATEST_SNAPDATE <<< "$COMMIT_INFO"

if [[ -n "$LATEST_COMMIT" ]]; then
    echo "   Latest commit:  ${LATEST_SHORT_COMMIT} (date: $LATEST_SNAPDATE)"

    if [[ "$CURRENT_COMMIT" != "$LATEST_COMMIT" ]]; then
        echo "   ✨ Update available: ${CURRENT_COMMIT:0:7} → ${LATEST_SHORT_COMMIT}"

        # Get commit count via GitHub compare API — much faster than a full clone.
        # ahead_by = how many commits the latest is ahead of our current spec commit.
        CURRENT_COUNT=$(grep -oP '^%global commits\s+\K[0-9]+' "$SPEC_FILE" || echo "0")
        COMPARE_DATA=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "compare" "$CURRENT_COMMIT" "$LATEST_COMMIT" 2>/dev/null || echo "")
        if [[ -n "$COMPARE_DATA" ]]; then
            AHEAD=$(echo "$COMPARE_DATA" | jq -r '.ahead_by // 0')
            COMMIT_COUNT=$((CURRENT_COUNT + AHEAD))
        else
            # Fallback: increment by 1 if compare API is unavailable
            COMMIT_COUNT=$((CURRENT_COUNT + 1))
        fi

        echo "   Commit count: $COMMIT_COUNT (was $CURRENT_COUNT, +$((COMMIT_COUNT - CURRENT_COUNT)) new)"

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
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
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
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
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
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
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
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release" 2>/dev/null || echo "")
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
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
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
# DANKSEARCH
# ============================================================================
echo ""
echo "📦 Checking danksearch..."

SPEC_FILE="danksearch/danksearch.spec"
UPSTREAM_REPO="AvengeMedia/danksearch"

# Get current version from spec
CURRENT_VERSION=$(grep -oP '^Version:\s+\K[0-9.]+' "$SPEC_FILE" || echo "unknown")
echo "   Current: $CURRENT_VERSION"

# Fetch latest release tag
LATEST_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release")
LATEST_VERSION="${LATEST_TAG#v}"

if [[ -n "$LATEST_VERSION" ]]; then
    echo "   Latest:  $LATEST_VERSION"

    if [[ "$CURRENT_VERSION" != "$LATEST_VERSION" ]]; then
        echo "   ✨ Update available: $CURRENT_VERSION → $LATEST_VERSION"

        # Update the spec file
        sed -i "s/^Version:\s\+.*/Version:        $LATEST_VERSION/" "$SPEC_FILE"

        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("danksearch: $CURRENT_VERSION → $LATEST_VERSION")
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
