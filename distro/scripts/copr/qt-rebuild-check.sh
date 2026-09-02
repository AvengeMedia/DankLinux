#!/usr/bin/env bash
# Bump Qt-linked specs when Fedora ships a new qt6 in a chroot this COPR builds for
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

COPR_OWNER="${COPR_OWNER:-avengemedia}"
COPR_PROJECT="${COPR_PROJECT:-danklinux}"
QT_WATCH_PACKAGES="${QT_WATCH_PACKAGES:-qt6-qtbase qt6-qtdeclarative qt6-qtwayland}"
QT_REBUILD_SPECS="${QT_REBUILD_SPECS:-distro/fedora/quickshell/quickshell.spec distro/fedora/quickshell/quickshell-git.spec distro/fedora/qt6ct-kde/qt6ct-kde.spec}"
QT_BASELINE="${QT_BASELINE:-distro/fedora/qt6-baseline.json}"
DNF="${DNF:-dnf5}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

read -ra PACKAGES <<<"$QT_WATCH_PACKAGES"
read -ra SPECS <<<"$QT_REBUILD_SPECS"

for tool in curl jq rpmdev-bumpspec rpmdev-vercmp "$DNF"; do
    if ! command -v "$tool" >/dev/null; then
        echo "::error::$tool not found" >&2
        exit 1
    fi
done

for spec in "${SPECS[@]}"; do
    if [[ ! -f "$spec" ]]; then
        echo "::error::spec missing: $spec" >&2
        exit 1
    fi
done

copr_chroots() {
    curl -fsSL "https://copr.fedorainfracloud.org/api_3/project?ownername=${COPR_OWNER}&projectname=${COPR_PROJECT}" \
        | jq -r '.chroot_repos | keys[]' \
        | grep -E '^fedora-([0-9]+|rawhide)-' \
        | sort -u
}

# rpmdev-vercmp exits 11 when the first EVR is newer, 12 when older, 0 when equal
newer_than() {
    local candidate="$1" current="$2" rc=0
    rpmdev-vercmp "$candidate" "$current" >/dev/null 2>&1 || rc=$?
    [[ $rc -eq 11 ]]
}

query_qt() {
    local rv="$1"
    "$DNF" repoquery -q --releasever="$rv" --repo=fedora,updates --refresh \
        --arch=x86_64 --latest-limit=1 --qf '%{name} %{evr}\n' "${PACKAGES[@]}"
}

label() {
    if [[ "$1" == rawhide ]]; then
        echo rawhide
    else
        echo "f$1"
    fi
}

# rpmdev-bumpspec refuses %autorelease specs; %autochangelog picks the commit message up instead
bump_spec() {
    local spec="$1" release n=0
    release=$(sed -nE 's/^Release:[[:space:]]+(.*)$/\1/p' "$spec" | head -1)
    if [[ "$release" != *%autorelease* ]]; then
        rpmdev-bumpspec -c "rebuild for $SUMMARY" "$spec"
        return
    fi
    if [[ "$release" =~ %autorelease\.([0-9]+) ]]; then
        n=${BASH_REMATCH[1]}
    fi
    sed -i -E "s/^(Release:[[:space:]]+)%autorelease(\.[0-9]+)?/\1%autorelease.$((n + 1))/" "$spec"
}

CHROOTS=$(copr_chroots)
if [[ -z "$CHROOTS" ]]; then
    echo "::error::no fedora chroots found for ${COPR_OWNER}/${COPR_PROJECT}" >&2
    exit 1
fi
RELEASEVERS=$(sed -E 's/^fedora-([^-]+)-.*/\1/' <<<"$CHROOTS" | sort -u)

BASELINE='{}'
if [[ -f "$QT_BASELINE" ]]; then
    BASELINE=$(cat "$QT_BASELINE")
fi
NEXT="$BASELINE"
CHANGES=()
CHANGED_RELEASEVERS=()
SEEDED=false

echo "Fedora releases from COPR chroots: $(echo "$RELEASEVERS" | tr '\n' ' ')"
for rv in $RELEASEVERS; do
    tag=$(label "$rv")
    found=$(query_qt "$rv")
    for pkg in "${PACKAGES[@]}"; do
        evr=$(awk -v p="$pkg" '$1 == p { print $2; exit }' <<<"$found")
        if [[ -z "$evr" ]]; then
            echo "::error::$pkg not found in $tag repos" >&2
            exit 1
        fi
        old=$(jq -r --arg rv "$rv" --arg p "$pkg" '.[$rv][$p] // empty' <<<"$BASELINE")
        if [[ -z "$old" ]]; then
            NEXT=$(jq --arg rv "$rv" --arg p "$pkg" --arg v "$evr" '.[$rv][$p] = $v' <<<"$NEXT")
            SEEDED=true
            echo "  $tag $pkg seeded at $evr"
            continue
        fi
        if [[ "$old" == "$evr" ]]; then
            echo "  $tag $pkg unchanged at $evr"
            continue
        fi
        if ! newer_than "$evr" "$old"; then
            echo "  $tag $pkg repo has $evr, older than baseline $old, ignoring"
            continue
        fi
        NEXT=$(jq --arg rv "$rv" --arg p "$pkg" --arg v "$evr" '.[$rv][$p] = $v' <<<"$NEXT")
        CHANGES+=("$pkg-$evr ($tag)")
        CHANGED_RELEASEVERS+=("$rv")
        echo "  $tag $pkg $old -> $evr"
    done
done

SUMMARY=""
BUILD_CHROOTS=""
BUMPED=false
if ((${#CHANGES[@]})); then
    SUMMARY=$(printf '%s, ' "${CHANGES[@]}")
    SUMMARY=${SUMMARY%, }
    for rv in $(printf '%s\n' "${CHANGED_RELEASEVERS[@]}" | sort -u); do
        BUILD_CHROOTS+="$(grep -E "^fedora-${rv}-" <<<"$CHROOTS" | tr '\n' ' ')"
    done
    BUILD_CHROOTS=${BUILD_CHROOTS% }
    for spec in "${SPECS[@]}"; do
        bump_spec "$spec"
        echo "  bumped $spec"
    done
    BUMPED=true
fi

DIRTY=false
if [[ "$SEEDED" == true || "$BUMPED" == true ]]; then
    jq -S . <<<"$NEXT" >"$QT_BASELINE"
    DIRTY=true
fi

{
    echo "bumped=$BUMPED"
    echo "dirty=$DIRTY"
    echo "summary=$SUMMARY"
    echo "chroots=$BUILD_CHROOTS"
} >>"$GITHUB_OUTPUT"

if [[ "$BUMPED" == true ]]; then
    echo "Rebuild needed: $SUMMARY"
    echo "Chroots: $BUILD_CHROOTS"
elif [[ "$SEEDED" == true ]]; then
    echo "Baseline seeded, no rebuild"
else
    echo "No qt6 changes"
fi
