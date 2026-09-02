#!/usr/bin/env bash
# Plan Debian (OBS) and Ubuntu (PPA) rebuilds of Qt private-ABI packages when qt6 moves
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$REPO_ROOT"

OBS_REPO_BASE="${OBS_REPO_BASE:-https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux}"
OBS_DEB_REPOS="${OBS_DEB_REPOS:-Debian_Unstable Debian_Testing Debian_13}"
PPA_OWNER="${PPA_OWNER:-avengemedia}"
PPA_NAME="${PPA_NAME:-danklinux}"
PPA_SERIES="${PPA_SERIES:-resolute stonking}"
LAUNCHPAD_API="${LAUNCHPAD_API:-https://api.launchpad.net/1.0}"
QT_DEB_PACKAGES="${QT_DEB_PACKAGES:-quickshell quickshell-git}"
QT_BASELINE="${QT_BASELINE:-distro/qt6-baseline-deb.json}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

read -ra OBS_REPOS <<<"$OBS_DEB_REPOS"
read -ra SERIES <<<"$PPA_SERIES"
read -ra PACKAGES <<<"$QT_DEB_PACKAGES"

for tool in curl jq dpkg; do
    if ! command -v "$tool" >/dev/null; then
        echo "::error::$tool not found" >&2
        exit 1
    fi
done

newer_than() {
    dpkg --compare-versions "$1" gt "$2"
}

upstream_part() {
    sed -E 's/^[0-9]+://; s/[+-].*//' <<<"$1"
}

db_suffix() {
    if [[ "$1" =~ \.?db([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo 1
    fi
}

ppa_suffix() {
    if [[ "$1" =~ ppa([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo 0
    fi
}

# prints "<version> <qt6-base-private-abi>" for the amd64 stanza of a package
obs_published() {
    local repo="$1" pkg="$2"
    curl -fsSL "$OBS_REPO_BASE/$repo/Packages" | awk -v want="$pkg" '
        /^Package: /      { cur = $2; ver = ""; arch = ""; abi = "" }
        /^Version: /      { ver = $2 }
        /^Architecture: / { arch = $2 }
        /^Depends: /      { if (match($0, /qt6-base-private-abi \(= [^)]+\)/)) abi = substr($0, RSTART + 24, RLENGTH - 25) }
        /^$/              { if (cur == want && arch == "amd64" && abi != "") { print ver, abi; exit } }
    '
}

launchpad_versions() {
    local url="$1"
    curl -fsSL "$url" | jq -r '.entries[].source_package_version'
}

archive_qt6_base() {
    local series="$1" best="" v
    while read -r v; do
        [[ -n "$v" ]] || continue
        if [[ -z "$best" ]] || newer_than "$v" "$best"; then
            best="$v"
        fi
    done < <(launchpad_versions "$LAUNCHPAD_API/ubuntu/+archive/primary?ws.op=getPublishedSources&source_name=qt6-base&exact_match=true&status=Published&distro_series=$LAUNCHPAD_API/ubuntu/$series")
    echo "$best"
}

ppa_published() {
    local pkg="$1" series="$2"
    launchpad_versions "$LAUNCHPAD_API/~$PPA_OWNER/+archive/ubuntu/$PPA_NAME?ws.op=getPublishedSources&source_name=$pkg&exact_match=true&status=Published&distro_series=$LAUNCHPAD_API/ubuntu/$series" | head -1
}

BASELINE='{}'
if [[ -f "$QT_BASELINE" ]]; then
    BASELINE=$(cat "$QT_BASELINE")
fi
NEXT="$BASELINE"
SEEDED=false
CHANGES=()
declare -A OBS_REBUILD=() OBS_VERSION=() PPA_REBUILD=()

echo "OBS Debian repos"
for repo in "${OBS_REPOS[@]}"; do
    for pkg in "${PACKAGES[@]}"; do
        read -r version abi < <(obs_published "$repo" "$pkg" || true)
        if [[ -z "${abi:-}" ]]; then
            echo "::error::$pkg not found in $repo Packages" >&2
            exit 1
        fi
        OBS_VERSION[$pkg]="$version"
        old=$(jq -r --arg r "$repo" --arg p "$pkg" '.obs[$r][$p] // empty' <<<"$BASELINE")
        if [[ -z "$old" ]]; then
            NEXT=$(jq --arg r "$repo" --arg p "$pkg" --arg v "$abi" '.obs[$r][$p] = $v' <<<"$NEXT")
            SEEDED=true
            echo "  $repo $pkg seeded at qt $abi ($version)"
            continue
        fi
        if [[ "$old" == "$abi" ]]; then
            echo "  $repo $pkg unchanged at qt $abi"
            continue
        fi
        if ! newer_than "$abi" "$old"; then
            echo "  $repo $pkg published against qt $abi, older than baseline $old, ignoring"
            continue
        fi
        NEXT=$(jq --arg r "$repo" --arg p "$pkg" --arg v "$abi" '.obs[$r][$p] = $v' <<<"$NEXT")
        OBS_REBUILD[$pkg]=1
        CHANGES+=("$repo $pkg qt $old -> $abi")
        echo "  $repo $pkg qt $old -> $abi"
    done
done

echo "Ubuntu series"
for series in "${SERIES[@]}"; do
    full=$(archive_qt6_base "$series")
    if [[ -z "$full" ]]; then
        echo "::error::qt6-base not found in Ubuntu $series" >&2
        exit 1
    fi
    qt=$(upstream_part "$full")
    old=$(jq -r --arg s "$series" '.ppa[$s] // empty' <<<"$BASELINE")
    if [[ -z "$old" ]]; then
        NEXT=$(jq --arg s "$series" --arg v "$qt" '.ppa[$s] = $v' <<<"$NEXT")
        SEEDED=true
        echo "  $series seeded at qt $qt ($full)"
        continue
    fi
    if [[ "$old" == "$qt" ]]; then
        echo "  $series unchanged at qt $qt ($full)"
        continue
    fi
    if ! newer_than "$qt" "$old"; then
        echo "  $series archive has qt $qt, older than baseline $old, ignoring"
        continue
    fi
    NEXT=$(jq --arg s "$series" --arg v "$qt" '.ppa[$s] = $v' <<<"$NEXT")
    PPA_REBUILD[$series]=1
    CHANGES+=("ubuntu $series qt $old -> $qt")
    echo "  $series qt $old -> $qt"
done

OBS_PLAN='[]'
for pkg in "${PACKAGES[@]}"; do
    [[ -n "${OBS_REBUILD[$pkg]:-}" ]] || continue
    next=$(( $(db_suffix "${OBS_VERSION[$pkg]}") + 1 ))
    OBS_PLAN=$(jq -c --arg p "$pkg" --argjson n "$next" '. + [{package: $p, rebuild: $n}]' <<<"$OBS_PLAN")
    echo "  obs: $pkg ${OBS_VERSION[$pkg]} -> .db$next"
done

PPA_PLAN='[]'
if ((${#PPA_REBUILD[@]})); then
    for pkg in "${PACKAGES[@]}"; do
        max=0
        for series in "${SERIES[@]}"; do
            n=$(ppa_suffix "$(ppa_published "$pkg" "$series")")
            (( n > max )) && max=$n
        done
        next=$((max + 1))
        for series in "${SERIES[@]}"; do
            [[ -n "${PPA_REBUILD[$series]:-}" ]] || continue
            PPA_PLAN=$(jq -c --arg t "$pkg:$series:$next" '. + [$t]' <<<"$PPA_PLAN")
            echo "  ppa: $pkg $series -> ppa$next"
        done
    done
fi

DIRTY=false
if [[ "$SEEDED" == true || ${#CHANGES[@]} -gt 0 ]]; then
    jq -S . <<<"$NEXT" >"$QT_BASELINE"
    DIRTY=true
fi

SUMMARY=""
if ((${#CHANGES[@]})); then
    SUMMARY=$(printf '%s, ' "${CHANGES[@]}")
    SUMMARY=${SUMMARY%, }
fi

{
    echo "dirty=$DIRTY"
    echo "summary=$SUMMARY"
    echo "obs_plan=$OBS_PLAN"
    echo "ppa_plan=$PPA_PLAN"
} >>"$GITHUB_OUTPUT"

if ((${#CHANGES[@]})); then
    echo "Rebuild needed: $SUMMARY"
elif [[ "$SEEDED" == true ]]; then
    echo "Baseline seeded, no rebuild"
else
    echo "No qt6 changes"
fi
