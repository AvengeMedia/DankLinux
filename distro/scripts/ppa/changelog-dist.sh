#!/usr/bin/env bash
# Helpers for reading Ubuntu dual-series debian/changelog files.

get_changelog_version_for_distribution() {
    local changelog="$1"
    local distribution="$2"

    [ -f "$changelog" ] || return 1

    awk -v dist="$distribution" '
        /^[^ ]+ \([^)]*\) [^;]+; urgency=/ {
            version = $0
            sub(/^[^ ]+ \(/, "", version)
            sub(/\).*/, "", version)

            distro = $0
            sub(/^[^ ]+ \([^)]*\) /, "", distro)
            sub(/;.*/, "", distro)

            if (distro == dist) {
                print version
                exit 0
            }
        }
    ' "$changelog"
}

changelog_max_series_version() {
    local changelog="$1"
    local first="${2:-resolute}"
    local second="${3:-stonking}"
    local first_version second_version

    first_version="$(get_changelog_version_for_distribution "$changelog" "$first" || true)"
    second_version="$(get_changelog_version_for_distribution "$changelog" "$second" || true)"

    if [[ -z "$first_version" ]]; then
        echo "$second_version"
        return
    fi
    if [[ -z "$second_version" ]]; then
        echo "$first_version"
        return
    fi

    if dpkg --compare-versions "$first_version" ge "$second_version"; then
        echo "$first_version"
    else
        echo "$second_version"
    fi
}

changelog_effective_version() {
    local package_dir="$1"
    local changelog="$package_dir/debian/changelog"

    [ -f "$changelog" ] || return 1

    if [[ "$package_dir" == */distro/ubuntu/* ]]; then
        changelog_max_series_version "$changelog" resolute stonking
    else
        sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' "$changelog"
    fi
}
