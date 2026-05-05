#!/usr/bin/env bash
# Auto-update package specs with latest versions from GitHub
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT/distro/fedora"

# Match PPA/OBS: -git RPM %%global tag is one patch above latest upstream stable release tag.
bump_patch_triplet() {
    local v="$1"
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
    else
        printf '%s\n' "$v"
    fi
}

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

# Sync %global tag with latest GitHub stable release + 1 patch (sorts above quickshell stable).
TAG_UPDATED=false
STABLE_REL_TAG=$("$SCRIPT_DIR/../common/fetch-version.sh" "$UPSTREAM_REPO" "release" 2>/dev/null || echo "")
STABLE_REL_VER="${STABLE_REL_TAG#v}"
if [[ -n "$STABLE_REL_VER" ]]; then
    DESIRED_GIT_TAG=$(bump_patch_triplet "$STABLE_REL_VER")
    CURRENT_GIT_TAG=$(grep -oP '^%global tag\s+\K[0-9.]+' "$SPEC_FILE" || echo "")
    if [[ -n "$DESIRED_GIT_TAG" && "$CURRENT_GIT_TAG" != "$DESIRED_GIT_TAG" ]]; then
        echo "   ✨ %global tag (ahead of stable $STABLE_REL_VER): $CURRENT_GIT_TAG → $DESIRED_GIT_TAG"
        sed -i "s/^%global tag\s\+.*/%global tag         $DESIRED_GIT_TAG/" "$SPEC_FILE"
        TAG_UPDATED=true
        UPDATED=$((UPDATED + 1))
        UPDATED_PACKAGES+=("quickshell-git: tag $CURRENT_GIT_TAG → $DESIRED_GIT_TAG")
    fi
else
    echo "   ⚠ Could not fetch stable release for tag sync (skipping %global tag bump)"
fi

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
        if [[ "$TAG_UPDATED" == true ]]; then
            echo "   ✓ Latest commit; %global tag synced to stable+patch"
        else
            echo "   ✓ Already up to date"
        fi
    fi
else
    echo "   ⚠ Could not fetch latest commit"
fi

# ---------------------------------------------------------------------------
# OpenSUSE quickshell-git: keep Version in sync with Fedora git spec (tag + commits + hash).
# ---------------------------------------------------------------------------
echo ""
echo "📦 Syncing OpenSUSE quickshell-git.spec..."

FEDORA_GIT_SPEC="$REPO_ROOT/distro/fedora/quickshell/quickshell-git.spec"
OBS_SPEC="$REPO_ROOT/distro/opensuse/quickshell-git.spec"

if [[ -f "$FEDORA_GIT_SPEC" && -f "$OBS_SPEC" ]]; then
    FG_TAG=$(grep -oP '^%global tag\s+\K[0-9.]+' "$FEDORA_GIT_SPEC" || echo "")
    FG_COMMIT=$(grep -oP '^%global commit\s+\K[a-f0-9]+' "$FEDORA_GIT_SPEC" || echo "")
    FG_COMMITS=$(grep -oP '^%global commits\s+\K[0-9]+' "$FEDORA_GIT_SPEC" || echo "")
    if [[ -n "$FG_TAG" && -n "$FG_COMMIT" && -n "$FG_COMMITS" ]]; then
        SHORT_HASH="${FG_COMMIT:0:8}"
        NEW_OBS_VER="${FG_TAG}+git${FG_COMMITS}.${SHORT_HASH}"
        CUR_OBS_VER=$(grep -oP '^Version:\s+\K\S+' "$OBS_SPEC" || echo "")
        if [[ "$CUR_OBS_VER" != "$NEW_OBS_VER" ]]; then
            echo "   ✨ OpenSUSE Version: $CUR_OBS_VER → $NEW_OBS_VER"
            sed -i "s/^Version:.*/Version:        $NEW_OBS_VER/" "$OBS_SPEC"
            UPDATED=$((UPDATED + 1))
            UPDATED_PACKAGES+=("opensuse/quickshell-git: $CUR_OBS_VER → $NEW_OBS_VER")
        else
            echo "   ✓ OpenSUSE Version already matches Fedora ($NEW_OBS_VER)"
        fi
    else
        echo "   ⚠ Missing %global tag/commit/commits in Fedora spec; skip OpenSUSE sync"
    fi
else
    echo "   ⚠ Fedora or OpenSUSE quickshell-git spec missing"
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
# Manual COPR RPM release versioning (workflow sets COPR_REBUILD_* env vars).
# Same mapping as copr-trigger.sh package names.
# ============================================================================
_copr_bump_spec_release() {
    local spec_rel="$1"
    local spec_path="$REPO_ROOT/$spec_rel"
    local i
    if [[ ! -f "$spec_path" ]]; then
        echo "::error::Spec missing: $spec_rel" >&2
        exit 1
    fi
    for ((i = 0; i < COPR_REBUILD_COUNT; i++)); do
        rpmdev-bumpspec -c "ci: COPR rebuild bump (workflow)" "$spec_path"
    done
    echo "✓ Bumped ${COPR_REBUILD_COUNT}x: $spec_rel"
}

if [[ -n "${COPR_REBUILD_COUNT:-}" || -n "${COPR_REBUILD_PACKAGE:-}" ]]; then
    if [[ -z "${COPR_REBUILD_COUNT:-}" || -z "${COPR_REBUILD_PACKAGE:-}" ]]; then
        echo "::error::Set both COPR_REBUILD_COUNT and COPR_REBUILD_PACKAGE or neither." >&2
        exit 1
    fi
    if ! [[ "${COPR_REBUILD_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
        echo "::error::COPR_REBUILD_COUNT must be a positive integer (got: ${COPR_REBUILD_COUNT})" >&2
        exit 1
    fi
    if ! command -v rpmdev-bumpspec &>/dev/null; then
        echo "::error::rpmdev-bumpspec not found; install rpmdevtools" >&2
        exit 1
    fi

    ALL_SPECS_BUMP=(
        distro/fedora/quickshell/quickshell.spec
        distro/fedora/quickshell/quickshell-git.spec
        distro/fedora/dgop/dgop.spec
        distro/fedora/cliphist/cliphist.spec
        distro/fedora/matugen/matugen.spec
        distro/fedora/breakpad/breakpad.spec
        distro/fedora/ghostty/ghostty.spec
        distro/fedora/fonts/material-symbols-fonts.spec
        distro/fedora/danksearch/danksearch.spec
        distro/fedora/cli11/cli11.spec
        distro/fedora/qt6ct-kde/qt6ct-kde.spec
        distro/fedora/cpptrace/cpptrace.spec
    )

    case "${COPR_REBUILD_PACKAGE}" in
        quickshell) _copr_bump_spec_release distro/fedora/quickshell/quickshell.spec ;;
        quickshell-git) _copr_bump_spec_release distro/fedora/quickshell/quickshell-git.spec ;;
        dgop) _copr_bump_spec_release distro/fedora/dgop/dgop.spec ;;
        cliphist) _copr_bump_spec_release distro/fedora/cliphist/cliphist.spec ;;
        matugen) _copr_bump_spec_release distro/fedora/matugen/matugen.spec ;;
        breakpad) _copr_bump_spec_release distro/fedora/breakpad/breakpad.spec ;;
        ghostty) _copr_bump_spec_release distro/fedora/ghostty/ghostty.spec ;;
        material-symbols-fonts) _copr_bump_spec_release distro/fedora/fonts/material-symbols-fonts.spec ;;
        danksearch) _copr_bump_spec_release distro/fedora/danksearch/danksearch.spec ;;
        cli11) _copr_bump_spec_release distro/fedora/cli11/cli11.spec ;;
        qt6ct-kde) _copr_bump_spec_release distro/fedora/qt6ct-kde/qt6ct-kde.spec ;;
        cpptrace) _copr_bump_spec_release distro/fedora/cpptrace/cpptrace.spec ;;
        all)
            for rel in "${ALL_SPECS_BUMP[@]}"; do
                _copr_bump_spec_release "$rel"
            done
            ;;
        *)
            echo "::error::Unknown package '${COPR_REBUILD_PACKAGE}' for COPR rebuild bump (niri/niri-git have no specs here)." >&2
            exit 1
            ;;
    esac
fi

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
