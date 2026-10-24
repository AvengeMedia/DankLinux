#!/usr/bin/env bash
# Stage and build Void XBPS packages dms-greeter / dms-greeter-git from a
# dux-greeter checkout (--source-dir, submodule checked out) using this repo's templates.
# Usage: void-build.sh <pkg> --source-dir=DIR [--version=X] [--force] [--smoke] [--void-packages=DIR]

set -euo pipefail

REPO="duxlabs-dev/dux-greeter"
PACKAGE="dms-greeter-git"
VERSION=""
SMOKE=false
FORCE_REBUILD=false
SOURCE_DIR="${SOURCE_DIR:-}"
VOID_PACKAGES_DIR="${VOID_PACKAGES_DIR:-}"
REPOSITORY_DIR="${REPOSITORY_DIR:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGING_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATE_ROOT="$PACKAGING_ROOT/distro/void/srcpkgs"

for arg in "$@"; do
    case "$arg" in
    dms-greeter|dms-greeter-git)
        PACKAGE="$arg"
        ;;
    --smoke)
        SMOKE=true
        ;;
    --force)
        FORCE_REBUILD=true
        ;;
    --version=*)
        VERSION="${arg#*=}"
        VERSION="${VERSION#v}"
        ;;
    --source-dir=*)
        SOURCE_DIR="${arg#*=}"
        SOURCE_DIR="${SOURCE_DIR/#\~/$HOME}"
        ;;
    --void-packages=*)
        VOID_PACKAGES_DIR="${arg#*=}"
        VOID_PACKAGES_DIR="${VOID_PACKAGES_DIR/#\~/$HOME}"
        ;;
    --repository-dir=*)
        REPOSITORY_DIR="${arg#*=}"
        REPOSITORY_DIR="${REPOSITORY_DIR/#\~/$HOME}"
        ;;
    -h|--help)
        sed -n '2,18p' "$0"
        exit 0
        ;;
    *)
        echo "Unknown argument: $arg" >&2
        exit 1
        ;;
    esac
done

if [[ -z "$SOURCE_DIR" ]]; then
    echo "ERROR: set --source-dir=DIR or SOURCE_DIR to a dux-greeter checkout" >&2
    exit 1
fi
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
if [[ ! -d "$SOURCE_DIR/core" ]] || ! git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: $SOURCE_DIR does not look like a dux-greeter git checkout" >&2
    exit 1
fi
if [[ ! -e "$SOURCE_DIR/dux-qml-common/DCommon/Widgets/DIcon.qml" ]]; then
    echo "ERROR: dux-qml-common submodule missing in $SOURCE_DIR. Run: git submodule update --init" >&2
    exit 1
fi
for p in "$VOID_PACKAGES_DIR" "$REPOSITORY_DIR"; do
    if [[ -n "$p" && "$p" != /* ]]; then
        echo "ERROR: --void-packages and --repository-dir must be absolute paths (got $p)" >&2
        exit 1
    fi
done

# All git operations run against the greeter checkout.
cd "$SOURCE_DIR"

git_version() {
    local base count hash
    base="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    [[ -z "$base" ]] && base="1.0.0"
    count="$(git rev-list --count HEAD)"
    hash="$(git rev-parse --short=8 HEAD)"
    # Void versions cannot contain '+'
    echo "${base}.git${count}.${hash}"
}

# Stage checkout + submodule into $1 (directory must exist / be empty-ish).
stage_checkout_tree() {
    local dest="$1"
    mkdir -p "$dest"
    git archive --format=tar HEAD | tar -x -C "$dest"
    rm -rf "$dest/dux-qml-common"
    mkdir -p "$dest/dux-qml-common"
    tar -C "$SOURCE_DIR/dux-qml-common" --exclude='.git' -cf - . \
        | tar -C "$dest/dux-qml-common" -xf -
    rm -rf "$dest/quickshell/DCommon"
    ln -sfn ../dux-qml-common/DCommon "$dest/quickshell/DCommon"
}

# Flat tarball for create_wrksrc=yes + build_wrksrc=core (dms-git pattern).
pack_git_source() {
    local dest_tarball="$1"
    local tmp
    tmp="$(mktemp -d)"
    # Expand path into trap now (set -u + EXIT after locals).
    trap 'rm -rf "'"$tmp"'"' EXIT

    stage_checkout_tree "$tmp"

    mkdir -p "$(dirname "$dest_tarball")"
    # Do not dereference symlinks here; sync-shell uses tar -h at build time.
    tar -C "$tmp" -czf "$dest_tarball" .
    rm -rf "$tmp"
    trap - EXIT

    if [[ ! -f "$dest_tarball" ]]; then
        echo "ERROR: failed to create $dest_tarball" >&2
        exit 1
    fi
    # Avoid grep -q (SIGPIPE + pipefail looks like failure even on match).
    if [[ "$(tar -tzf "$dest_tarball" | grep -c 'core/' || true)" -lt 1 ]]; then
        echo "ERROR: packed tarball missing top-level core/ (not flat?)" >&2
        tar -tzf "$dest_tarball" | head -20 >&2 || true
        exit 1
    fi
}

# Nested tarball dank-greeter-$ver/... (stable Void template, no create_wrksrc).
pack_stable_source() {
    local dest_tarball="$1"
    local ver="$2"
    local tmp top
    tmp="$(mktemp -d)"
    trap 'rm -rf "'"$tmp"'"' EXIT
    top="$tmp/dank-greeter-${ver}"
    mkdir -p "$top"
    stage_checkout_tree "$top"

    mkdir -p "$(dirname "$dest_tarball")"
    tar -C "$tmp" -czf "$dest_tarball" "dank-greeter-${ver}"
    rm -rf "$tmp"
    trap - EXIT

    if [[ "$(tar -tzf "$dest_tarball" | grep -c "dank-greeter-${ver}/core/" || true)" -lt 1 ]]; then
        echo "ERROR: stable tarball missing dank-greeter-${ver}/core/" >&2
        tar -tzf "$dest_tarball" | head -20 >&2 || true
        exit 1
    fi
}

require_tar_on_path() {
    if ! command -v tar &>/dev/null; then
        echo "ERROR: tar not on PATH (Void hostmakedepends must include tar)" >&2
        exit 1
    fi
}

check_template_has_tar() {
    local tmpl="$TEMPLATE_ROOT/${PACKAGE}/template"
    if ! grep -qE '^hostmakedepends=.*\btar\b' "$tmpl"; then
        echo "ERROR: $tmpl hostmakedepends must include tar (sync-shell needs it)" >&2
        exit 1
    fi
}

run_sync_shell_smoke() {
    local core_dir="$1"
    require_tar_on_path
    make -C "$core_dir" sync-shell
    test -f "$core_dir/internal/shellembed/dist/DCommon/Widgets/DIcon.qml"
}

smoke_git() {
    local ver tarball extract
    ver="$(git_version)"
    tarball="$(mktemp /tmp/dms-greeter-git-XXXXXX.tar.gz)"
    extract="$(mktemp -d)"
    trap 'rm -rf "'"$extract"'"; rm -f "'"$tarball"'"' EXIT

    check_template_has_tar
    echo "==> Smoke: packing flat git source ($ver)"
    pack_git_source "$tarball"

    echo "==> Smoke: extract + make sync-shell"
    tar -xzf "$tarball" -C "$extract"
    if [[ ! -d "$extract/core" ]]; then
        echo "ERROR: extract missing core/" >&2
        exit 1
    fi
    run_sync_shell_smoke "$extract/core"

    echo "==> Smoke OK: dms-greeter-git flat pack + sync-shell"
    rm -rf "$extract"
    rm -f "$tarball"
    trap - EXIT
}

smoke_stable() {
    local ver tarball extract
    ver="${VERSION}"
    if [[ -z "$ver" ]]; then
        ver="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
        [[ -z "$ver" ]] && ver="1.0.0"
    fi
    tarball="$(mktemp /tmp/dms-greeter-XXXXXX.tar.gz)"
    extract="$(mktemp -d)"
    trap 'rm -rf "'"$extract"'"; rm -f "'"$tarball"'"' EXIT

    check_template_has_tar
    echo "==> Smoke: packing nested stable source (dank-greeter-${ver}/)"
    pack_stable_source "$tarball" "$ver"

    echo "==> Smoke: extract + make sync-shell"
    tar -xzf "$tarball" -C "$extract"
    if [[ ! -d "$extract/dank-greeter-${ver}/core" ]]; then
        echo "ERROR: extract missing dank-greeter-${ver}/core/" >&2
        exit 1
    fi
    run_sync_shell_smoke "$extract/dank-greeter-${ver}/core"

    echo "==> Smoke OK: dms-greeter nested pack + sync-shell"
    rm -rf "$extract"
    rm -f "$tarball"
    trap - EXIT
}

patch_git_template() {
    local void_pkgs="$1" ver="$2" tarball="$3" checksum
    checksum="$(sha256sum "$tarball" | cut -d' ' -f1)"
    sed -i "s/^version=.*/version=${ver}/" "$void_pkgs/srcpkgs/dms-greeter-git/template"
    sed -i "s/^checksum=.*/checksum=${checksum}/" "$void_pkgs/srcpkgs/dms-greeter-git/template"
    sed -i "s|^distfiles=.*|distfiles=\"dms-greeter-git-${ver}.tar.gz\"|" \
        "$void_pkgs/srcpkgs/dms-greeter-git/template"
}

build_git_xbps() {
    local void_pkgs="$1"
    local ver tarball rev expected
    ver="$(git_version)"
    echo "==> Preparing dms-greeter-git version $ver (from $(git rev-parse HEAD))"

    tarball="$void_pkgs/hostdir/sources/dms-greeter-git-${ver}/dms-greeter-git-${ver}.tar.gz"
    mkdir -p "$(dirname "$tarball")"
    pack_git_source "$tarball"
    patch_git_template "$void_pkgs" "$ver" "$tarball"

    rev="$(grep -E '^revision=' "$void_pkgs/srcpkgs/dms-greeter-git/template" | cut -d= -f2 | tr -d '"')"
    expected="dms-greeter-git-${ver}_${rev}.x86_64.xbps"

    if [[ -n "$REPOSITORY_DIR" ]] && [[ -f "$REPOSITORY_DIR/current/$expected" ]] && [[ "$FORCE_REBUILD" != true ]]; then
        echo "✅ $expected already exists, skipping build."
        return 0
    fi

    echo "🔨 Compiling dms-greeter-git via xbps-src..."
    (cd "$void_pkgs" && ./xbps-src pkg dms-greeter-git)

    if [[ -n "$REPOSITORY_DIR" ]]; then
        mkdir -p "$REPOSITORY_DIR/current"
        rm -f "$REPOSITORY_DIR/current/${expected}"
        cp -L "$void_pkgs/hostdir/binpkgs/${expected}" "$REPOSITORY_DIR/current/"
        echo "Copied $expected -> $REPOSITORY_DIR/current/"
    fi
}

build_stable_xbps() {
    local void_pkgs="$1"
    local ver="${VERSION}"
    if [[ -z "$ver" ]]; then
        ver="$(curl -fsSL ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name' | sed 's/^v//')"
    fi
    if [[ -z "$ver" ]] || [[ "$ver" == "null" ]]; then
        echo "ERROR: Could not determine stable version (pass --version=)" >&2
        exit 1
    fi

    echo "==> Preparing dms-greeter version $ver"
    local tarball checksum rev expected
    rev="$(grep -E '^revision=' "$void_pkgs/srcpkgs/dms-greeter/template" | cut -d= -f2 | tr -d '"')"
    expected="dms-greeter-${ver}_${rev}.x86_64.xbps"

    if [[ -n "$REPOSITORY_DIR" ]] && [[ -f "$REPOSITORY_DIR/current/$expected" ]] && [[ "$FORCE_REBUILD" != true ]]; then
        echo "✅ $expected already exists, skipping build."
        return 0
    fi

    # Tolerate the window where the release exists but its tarball asset is not uploaded yet.
    tarball="$(mktemp)"
    if ! curl -fsSL -o "$tarball" \
        "https://github.com/${REPO}/releases/download/v${ver}/dank-greeter-${ver}.tar.gz"; then
        rm -f "$tarball"
        echo "⚠️  dank-greeter-${ver}.tar.gz is not available yet for v${ver}; skipping stable build this run." >&2
        return 0
    fi
    checksum="$(sha256sum "$tarball" | cut -d' ' -f1)"
    rm -f "$tarball"

    sed -i "s/^version=.*/version=${ver}/" "$void_pkgs/srcpkgs/dms-greeter/template"
    sed -i "s/^checksum=.*/checksum=${checksum}/" "$void_pkgs/srcpkgs/dms-greeter/template"

    echo "🔨 Compiling dms-greeter via xbps-src..."
    (cd "$void_pkgs" && ./xbps-src pkg dms-greeter)

    if [[ -n "$REPOSITORY_DIR" ]]; then
        mkdir -p "$REPOSITORY_DIR/current"
        rm -f "$REPOSITORY_DIR/current/${expected}"
        cp -L "$void_pkgs/hostdir/binpkgs/${expected}" "$REPOSITORY_DIR/current/"
        echo "Copied $expected -> $REPOSITORY_DIR/current/"
    fi
}

if [[ "$SMOKE" == true ]]; then
    if [[ "$PACKAGE" == "dms-greeter-git" ]]; then
        smoke_git
    else
        smoke_stable
    fi
    exit 0
fi

if [[ -z "$VOID_PACKAGES_DIR" ]]; then
    echo "ERROR: set --void-packages=DIR or VOID_PACKAGES_DIR (or use --smoke)" >&2
    exit 1
fi
if [[ ! -x "$VOID_PACKAGES_DIR/xbps-src" ]]; then
    echo "ERROR: $VOID_PACKAGES_DIR does not look like void-packages (missing xbps-src)" >&2
    exit 1
fi

# Ensure templates are present in void-packages
if [[ ! -f "$VOID_PACKAGES_DIR/srcpkgs/${PACKAGE}/template" ]]; then
    echo "==> Installing template into void-packages/srcpkgs/${PACKAGE}"
    cp -R "$TEMPLATE_ROOT/${PACKAGE}" "$VOID_PACKAGES_DIR/srcpkgs/"
fi

if [[ "$PACKAGE" == "dms-greeter-git" ]]; then
    build_git_xbps "$VOID_PACKAGES_DIR"
else
    build_stable_xbps "$VOID_PACKAGES_DIR"
fi
