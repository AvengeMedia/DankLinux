#!/bin/bash
# Unified OBS status checker for danklinux packages
# Checks all platforms (Debian, OpenSUSE) and architectures (x86_64, aarch64)
# Usage: ./distro/scripts/obs/obs-status.sh [package-name] [--logs]
#
# By default prints a compact status grid and brief failure hints.
# Pass --logs for full build log tails (slower).

set -euo pipefail

OBS_BASE_PROJECT="home:AvengeMedia:danklinux"
OBS_BASE="$HOME/.cache/osc-checkouts"

ALL_PACKAGES=(matugen matugen-snapshot niri niri-git quickshell quickshell-git xwayland-satellite xwayland-satellite-git danksearch dgop ghostty dankcalendar-git)
REPOS=("Debian_13" "Debian_Testing" "Debian_Unstable" "openSUSE_Tumbleweed" "openSUSE_Slowroll" "16.0" "16.1")
ARCHES=("x86_64" "aarch64")

FETCH_LOGS=false
PACKAGE_ARG=""

for arg in "$@"; do
    case "$arg" in
        --logs) FETCH_LOGS=true ;;
        -h|--help)
            echo "Usage: $0 [package-name] [--logs]"
            exit 0
            ;;
        *)
            if [[ -z "$PACKAGE_ARG" ]]; then
                PACKAGE_ARG="$arg"
            else
                echo "Unknown argument: $arg" >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -n "$PACKAGE_ARG" ]]; then
    PACKAGES=("$PACKAGE_ARG")
else
    PACKAGES=("${ALL_PACKAGES[@]}")
fi

TOTAL_OK=0
TOTAL_FAIL=0
TOTAL_UNRES=0
TOTAL_DISABLED=0
TOTAL_PENDING=0

print_status_line() {
    local repo="$1" arch="$2" status="$3"
    local color symbol

    case "$status" in
        succeeded*)
            color="\033[0;32m"; symbol="✅"
            ((TOTAL_OK++)) || true
            ;;
        failed)
            color="\033[0;31m"; symbol="❌"
            ((TOTAL_FAIL++)) || true
            ;;
        unresolvable)
            color="\033[0;33m"; symbol="⚠️"
            ((TOTAL_UNRES++)) || true
            ;;
        disabled|excluded|removed)
            color="\033[0;90m"; symbol="⏸"
            ((TOTAL_DISABLED++)) || true
            ;;
        building|scheduled|finished)
            color="\033[0;37m"; symbol="⏳"
            ((TOTAL_PENDING++)) || true
            ;;
        *)
            color="\033[0;33m"; symbol="?"
            ;;
    esac

    echo -e "  $symbol $repo $arch: ${color}${status}\033[0m"
}

fetch_brief_failure() {
    local pkg="$1" repo="$2" arch="$3" status="$4"
    local results_v="$5"

    echo ""
    echo "  ── $repo $arch ($status) ──"

    if [[ "$status" == "unresolvable" ]]; then
        local detailed
        detailed=$(echo "$results_v" | awk "/^${repo}.*${arch}.*unresolvable:/{getline; print}" | sed -e 's/^[[:space:]]*//' || true)
        if [[ -n "$detailed" ]]; then
            echo "  Reason: $detailed"
        fi
        if REASON=$(osc api "/build/$OBS_BASE_PROJECT/$repo/$arch/$pkg/_reason" 2>&1); then
            if echo "$REASON" | grep -q "<explain>"; then
                echo "  OBS: $(echo "$REASON" | grep -oP '<explain>\K[^<]*' || true)"
            fi
        fi
        return
    fi

    # failed: grep last meaningful errors from build log (fast, no full download)
    osc remotebuildlog "$OBS_BASE_PROJECT" "$pkg" "$repo" "$arch" 2>&1 | \
        rg -i "error:|fatal error|unresolvable|nothing provides|failed \"build" | tail -8 || \
        echo "  (no error lines found — try --logs)"
}

fetch_full_log() {
    local pkg="$1" repo="$2" arch="$3" status="$4"
    local results_v="$5"

    echo ""
    echo "  ────────────────────────────────────────────"
    echo "  Build log: $repo $arch"
    echo "  ────────────────────────────────────────────"

    if [[ "$status" == "unresolvable" ]]; then
        fetch_brief_failure "$pkg" "$repo" "$arch" "$status" "$results_v"
        return
    fi

    osc remotebuildlog "$OBS_BASE_PROJECT" "$pkg" "$repo" "$arch" 2>&1 | tail -80 || true
}

mkdir -p "$OBS_BASE"
cd "$OBS_BASE"

for pkg in "${PACKAGES[@]}"; do
    echo "=========================================="
    echo "=== $pkg ==="
    echo "=========================================="
    PKG_DIR="$OBS_BASE/$OBS_BASE_PROJECT/$pkg"

    if [[ ! -d "$PKG_DIR" ]]; then
        if ! (cd "$OBS_BASE" && osc co "$OBS_BASE_PROJECT/$pkg" 2>&1 | tail -1); then
            echo "  Failed to checkout OBS package: $pkg"
            echo ""
            continue
        fi
    fi

    if [[ ! -d "$PKG_DIR" ]]; then
        echo "  Checkout did not create expected directory: $PKG_DIR"
        echo ""
        continue
    fi

    pushd "$PKG_DIR" > /dev/null

    if ! ALL_RESULTS=$(osc results 2>&1); then
        echo "  Failed to fetch build results for $pkg"
        echo "$ALL_RESULTS" | tail -20
        echo ""
        popd > /dev/null
        continue
    fi

    NEEDS_VERBOSE=false
    if echo "$ALL_RESULTS" | grep -q "unresolvable"; then
        NEEDS_VERBOSE=true
    fi

    ALL_RESULTS_V=""
    if [[ "$NEEDS_VERBOSE" == "true" ]]; then
        ALL_RESULTS_V=$(osc results -v 2>&1 || true)
    fi

    PROBLEM_BUILDS=()

    for repo in "${REPOS[@]}"; do
        for arch in "${ARCHES[@]}"; do
            STATUS=$(echo "$ALL_RESULTS" | awk -v r="$repo" -v a="$arch" '$1 == r && $2 == a { print $NF; exit }' || true)

            if [[ -n "$STATUS" ]]; then
                print_status_line "$repo" "$arch" "$STATUS"
                case "$STATUS" in
                    failed|unresolvable)
                        PROBLEM_BUILDS+=("$repo $arch $STATUS")
                        ;;
                esac
            fi
        done
    done

    if [[ ${#PROBLEM_BUILDS[@]} -gt 0 ]]; then
        if [[ "$FETCH_LOGS" == "true" ]]; then
            echo ""
            echo "  📋 Fetching logs for failed/unresolvable builds..."
            for build in "${PROBLEM_BUILDS[@]}"; do
                read -r repo arch status <<< "$build"
                fetch_full_log "$pkg" "$repo" "$arch" "$status" "$ALL_RESULTS_V"
            done
        else
            echo ""
            echo "  📋 Failure summary (use --logs for full build logs):"
            for build in "${PROBLEM_BUILDS[@]}"; do
                read -r repo arch status <<< "$build"
                fetch_brief_failure "$pkg" "$repo" "$arch" "$status" "$ALL_RESULTS_V"
            done
        fi
    fi

    echo ""
    popd > /dev/null
done

echo "=========================================="
echo "Status check complete!"
echo "  ✅ succeeded: $TOTAL_OK  ❌ failed: $TOTAL_FAIL  ⚠️ unresolvable: $TOTAL_UNRES  ⏸ disabled: $TOTAL_DISABLED  ⏳ pending: $TOTAL_PENDING"
if [[ "$FETCH_LOGS" == "false" && $(( TOTAL_FAIL + TOTAL_UNRES )) -gt 0 ]]; then
    echo "  Tip: re-run with --logs for full build log output"
fi
