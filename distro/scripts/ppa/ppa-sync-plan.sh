#!/usr/bin/env bash
# Build a per-series upload plan by comparing upstream state with Launchpad.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FETCH_VERSION="$SCRIPT_DIR/../common/fetch-version.sh"

PPA_OWNER="avengemedia"
PPA_NAME="danklinux"
LAUNCHPAD_API="https://api.launchpad.net/1.0"
SERIES_LIST=(resolute stonking)
PACKAGE_FILTER="auto"
REBUILD_RELEASE=""
JSON=false

PACKAGES=(
    "cliphist:sentriz/cliphist:release"
    "ghostty:ghostty-org/ghostty:release"
    "matugen:InioX/matugen:release"
    "niri:niri-wm/niri:release"
    "niri-git:niri-wm/niri:git"
    "quickshell:quickshell-mirror/quickshell:release"
    "quickshell-git:quickshell-mirror/quickshell:git"
    "xwayland-satellite:Supreeeme/xwayland-satellite:release"
    "xwayland-satellite-git:Supreeeme/xwayland-satellite:git"
    "dankcalendar-git:AvengeMedia/dankcalendar:git"
)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package)
            PACKAGE_FILTER="$2"
            shift 2
            ;;
        --rebuild)
            REBUILD_RELEASE="$2"
            shift 2
            ;;
        --json)
            JSON=true
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

gh_curl() {
    local url="$1"
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "$url"
    else
        curl -fsSL "$url"
    fi
}

latest_release() {
    local repo="$1"
    "$FETCH_VERSION" "$repo" release | sed 's/^v//'
}

latest_commit() {
    local repo="$1"
    local data
    data="$(gh_curl "https://api.github.com/repos/${repo}/commits/main" 2>/dev/null || gh_curl "https://api.github.com/repos/${repo}/commits/master")"
    echo "$data" | jq -r '.sha // empty'
}

published_version() {
    local package="$1"
    local series="$2"
    local series_url="https%3A%2F%2Fapi.launchpad.net%2F1.0%2Fubuntu%2F${series}"
    local url="${LAUNCHPAD_API}/~${PPA_OWNER}/+archive/ubuntu/${PPA_NAME}?ws.op=getPublishedSources&source_name=${package}&status=Published&distro_series=${series_url}"

    curl -fsSL "$url" 2>/dev/null | jq -r '.entries[0].source_package_version // empty'
}

release_base() {
    echo "$1" | sed -E 's/ppa[0-9]+$//' | sed -E 's/-[0-9]+$//'
}

ppa_suffix() {
    local version="$1"
    if [[ "$version" =~ ppa([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

embedded_commit() {
    echo "$1" | sed -nE 's/.*[+~](git|snapshot|pin)[0-9]+\.([a-f0-9]{7,12}).*/\2/p'
}

target_ppa() {
    local series="$1"
    if [[ -n "$REBUILD_RELEASE" ]]; then
        if [[ "$series" == "stonking" ]]; then
            echo $((REBUILD_RELEASE + 1))
        else
            echo "$REBUILD_RELEASE"
        fi
    elif [[ "$series" == "stonking" ]]; then
        echo "2"
    else
        echo "1"
    fi
}

rebuild_release_is_newer() {
    local series="$1"
    local published="$2"
    local requested current

    [[ -n "$REBUILD_RELEASE" ]] || return 1

    requested="$(target_ppa "$series")"
    current="$(ppa_suffix "$published")"
    [[ "$requested" -gt "$current" ]]
}

expected_release_base() {
    local package="$1"
    local repo="$2"
    local series="$3"
    local latest override os_pin snapshot_enabled snapshot_base

    latest="$(latest_release "$repo")"

    if [[ "$package" == "quickshell" && -f "$REPO_ROOT/distro/snapshots.yaml" ]] && command -v yq >/dev/null 2>&1; then
        snapshot_enabled="$(yq eval '.quickshell.enabled' "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "false")"
        snapshot_base="$(yq eval '.quickshell.base_version' "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "")"
        if [[ "$snapshot_enabled" == "true" && -n "$snapshot_base" ]]; then
            if dpkg --compare-versions "$latest" gt "$snapshot_base"; then
                echo "$latest"
            else
                local snap_count snap_commit
                snap_count="$(yq eval '.quickshell.commit_count' "$REPO_ROOT/distro/snapshots.yaml")"
                snap_commit="$(yq eval '.quickshell.commit' "$REPO_ROOT/distro/snapshots.yaml")"
                echo "${snapshot_base}.1+snapshot${snap_count}.${snap_commit:0:8}"
            fi
            return
        fi
    fi

    if [[ -f "$REPO_ROOT/distro/snapshots.yaml" ]] && command -v yq >/dev/null 2>&1; then
        os_pin="$(yq eval ".${package}.os_pins.${series}" "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "null")"
        if [[ "$os_pin" != "null" && -n "$os_pin" ]]; then
            latest="$os_pin"
        fi
        override="$(yq eval ".${package}.ppa_version_override.${series}" "$REPO_ROOT/distro/snapshots.yaml" 2>/dev/null || echo "null")"
        if [[ "$override" != "null" && -n "$override" ]]; then
            latest="$override"
        fi
    fi

    echo "$latest"
}

include_package() {
    local package="$1"
    [[ "$PACKAGE_FILTER" == "auto" || "$PACKAGE_FILTER" == "all" || "$PACKAGE_FILTER" == "$package" ]]
}

TARGETS=()

for pkg_info in "${PACKAGES[@]}"; do
    IFS=':' read -r package repo type <<< "$pkg_info"
    include_package "$package" || continue

    if [[ "$type" == "git" ]]; then
        expected_commit="$(latest_commit "$repo")"
        expected_label="${expected_commit:0:8}"
    else
        expected_label=""
    fi

    for series in "${SERIES_LIST[@]}"; do
        if [[ "$type" == "release" ]]; then
            expected_base="$(expected_release_base "$package" "$repo" "$series")"
            expected_label="$expected_base"
        fi

        ppa_version="$(published_version "$package" "$series")"
        needs_update=false
        reason=""

        if [[ -z "$ppa_version" ]]; then
            needs_update=true
            reason="missing from ${series}"
        elif [[ "$type" == "git" ]]; then
            ppa_commit="$(embedded_commit "$ppa_version")"
            if [[ -z "$ppa_commit" || "${expected_commit:0:${#ppa_commit}}" != "$ppa_commit" ]]; then
                needs_update=true
                reason="commit ${ppa_commit:-none} -> ${expected_commit:0:8}"
            fi
        else
            ppa_base="$(release_base "$ppa_version")"
            if [[ "$ppa_base" != "$expected_base" ]]; then
                needs_update=true
                reason="version ${ppa_base:-none} -> ${expected_base}"
            fi
        fi

        if [[ "$needs_update" != "true" ]] && rebuild_release_is_newer "$series" "$ppa_version"; then
            needs_update=true
            reason="rebuild ppa$(ppa_suffix "$ppa_version") -> ppa$(target_ppa "$series")"
        fi

        if [[ "$needs_update" == "true" ]]; then
            target="${package}:${series}:$(target_ppa "$series")"
            TARGETS+=("$target")
            echo "${package}/${series}: ${reason} (published: ${ppa_version:-none}, target: ${expected_label})" >&2
        else
            echo "${package}/${series}: current (${ppa_version})" >&2
        fi
    done
done

if [[ "$JSON" == "true" ]]; then
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${TARGETS[@]}" | jq -R -s -c 'split("\n")[:-1]'
    fi
else
    echo "${TARGETS[*]}"
fi
