%global zig_minimum_version 0.15.0
%global ghostty_libdir /usr/lib
%global ghostty_systemd_user_unitdir %{_userunitdir}

Name:           ghostty
Version:        1.3.1
Release:        1%{?dist}
Summary:        Fast, feature-rich, and cross-platform terminal emulator that uses platform-native UI and GPU acceleration

License:        MIT
URL:            https://github.com/ghostty-org/ghostty
Source0:        ghostty-%{version}.tar.xz

BuildRequires:  zig15
BuildRequires:  curl
BuildRequires:  blueprint-compiler
BuildRequires:  fontconfig-devel
BuildRequires:  freetype-devel
BuildRequires:  glib2-devel
BuildRequires:  gtk4-devel
BuildRequires:  gtk4-layer-shell-devel
BuildRequires:  harfbuzz-devel
BuildRequires:  libadwaita-devel
BuildRequires:  libpng-devel
BuildRequires:  ncurses-devel
BuildRequires:  oniguruma-devel
BuildRequires:  pkg-config
BuildRequires:  wayland-protocols-devel
BuildRequires:  zlib-ng-devel
BuildRequires:  libpixman-1-0-devel

Requires:       fontconfig
Requires:       libfreetype6
Requires:       glib2
Requires:       libgtk-4-1
Requires:       libgtk4-layer-shell0
Requires:       libharfbuzz0
Requires:       libadwaita-1-0
Requires:       libpng16-16
Requires:       libonig5
Requires:       libpixman-1-0
Requires:       libz1

%description
Ghostty is a fast, feature-rich, and cross-platform terminal emulator that
uses platform-native UI and GPU acceleration. It provides standards-compliant
terminal emulation with modern features like ligature support, custom shaders,
and native OS integration.

%prep
%setup -q

# Normalize vendored dependency URLs for offline/reproducible builds.
THEMES_FILE="file://$PWD/ghostty-themes.tgz"
if [ -f "$PWD/ghostty-themes.tgz" ]; then
    sed -i "s#https://deps.files.ghostty.org/ghostty-themes-release-[^\"]*\.tgz#${THEMES_FILE}#" build.zig.zon
    sed -i "s#https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/.\+/ghostty-themes.tgz#${THEMES_FILE}#" build.zig.zon
    sed -i '/\.iterm2_themes/,/}/ s|\.hash = "[^"]\+"|.hash = "N-V-__8AABVbAwBwDRyZONfx553tvMW8_A2OKUoLzPUSRiLF"|' build.zig.zon
fi
if [ -f "$PWD/wayland.tar.gz" ]; then
    sed -i "s#https://deps.files.ghostty.org/wayland-9cb3d7aa9dc995ffafdbdef7ab86a949d0fb0e7d.tar.gz#file://$PWD/wayland.tar.gz#" build.zig.zon
fi
if [ -f "$PWD/wayland-protocols.tar.gz" ]; then
    sed -i "s#https://deps.files.ghostty.org/wayland-protocols-258d8f88f2c8c25a830c6316f87d23ce1a0f12d9.tar.gz#file://$PWD/wayland-protocols.tar.gz#" build.zig.zon
fi
if [ -f "$PWD/plasma_wayland_protocols.tar.gz" ]; then
    sed -i "s#https://deps.files.ghostty.org/plasma_wayland_protocols-12207e0851c12acdeee0991e893e0132fc87bb763969a585dc16ecca33e88334c566.tar.gz#file://$PWD/plasma_wayland_protocols.tar.gz#" build.zig.zon
fi
HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES"
if [ ! -d /usr/include/harfbuzz ] || ! grep -R -q "HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES" /usr/include/harfbuzz 2>/dev/null; then
    if grep -R -q "HB_BUFFER_CLUSTER_LEVEL_CHARACTERS" /usr/include/harfbuzz 2>/dev/null; then
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_CHARACTERS + 3"
    elif grep -R -q "HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES" /usr/include/harfbuzz 2>/dev/null; then
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES + 3"
    else
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS + 3"
    fi
fi
find . -type f -path "*/pkg/harfbuzz/buffer.zig" -exec \
    sed -i "s/enum(u2)/enum(u8)/" {} + || true
find . -type f -path "*/pkg/harfbuzz/buffer.zig" -exec \
    sed -i "s/graphemes = c.HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES/graphemes = ${HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES}/" {} + || true

ZIG_GLOBAL_CACHE_DIR=$PWD/zig-deps
# Skip fetch-zig-cache when zig-deps pre-vendored (OBS source tarball has no network)
if [ -d "$ZIG_GLOBAL_CACHE_DIR/p" ] && [ -n "$(ls -A "$ZIG_GLOBAL_CACHE_DIR/p" 2>/dev/null)" ]; then
    echo "Using pre-vendored zig-deps from source package"
elif [ -x ./nix/build-support/fetch-zig-cache.sh ]; then
    ZIG_GLOBAL_CACHE_DIR=$ZIG_GLOBAL_CACHE_DIR ./nix/build-support/fetch-zig-cache.sh
else
    echo "WARNING: fetch-zig-cache.sh not found; proceeding with direct network access."
fi

%build
export ZIG_GLOBAL_CACHE_DIR=$PWD/zig-deps
HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES"
if [ ! -d /usr/include/harfbuzz ] || ! grep -R -q "HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES" /usr/include/harfbuzz 2>/dev/null; then
    if grep -R -q "HB_BUFFER_CLUSTER_LEVEL_CHARACTERS" /usr/include/harfbuzz 2>/dev/null; then
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_CHARACTERS + 3"
    elif grep -R -q "HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES" /usr/include/harfbuzz 2>/dev/null; then
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES + 3"
    else
        HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES="c.HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS + 3"
    fi
fi
find . -type f -path "*/pkg/harfbuzz/buffer.zig" -exec \
    sed -i "s/enum(u2)/enum(u8)/" {} + || true
find . -type f -path "*/pkg/harfbuzz/buffer.zig" -exec \
    sed -i "s/graphemes = c.HB_BUFFER_CLUSTER_LEVEL_GRAPHEMES/graphemes = ${HARFBUZZ_CLUSTER_LEVEL_GRAPHEMES}/" {} + || true

mkdir -p %{_builddir}/ghostty-buildroot
if [ -d "$ZIG_GLOBAL_CACHE_DIR/p" ]; then
    if [ -x "%{_bindir}/zig-0.15" ]; then
        ZIG_BIN="%{_bindir}/zig-0.15"
    elif [ -x "%{_bindir}/zig" ]; then
        ZIG_BIN="%{_bindir}/zig"
    else
        echo "ERROR: zig compiler not found in %{_bindir}"
        exit 1
    fi
    DESTDIR=%{_builddir}/ghostty-buildroot "$ZIG_BIN" build install \
        --system "$ZIG_GLOBAL_CACHE_DIR/p" \
        --summary all \
        --prefix "%{_prefix}" \
        -Dversion-string=%{version}-%{release} \
        -Doptimize=ReleaseFast \
        -Dcpu=baseline \
        -Dpie=true \
        -Demit-docs=false
else
    echo "WARNING: Zig cache directory not found at $ZIG_GLOBAL_CACHE_DIR/p; building without --system."
    if [ -x "%{_bindir}/zig-0.15" ]; then
        ZIG_BIN="%{_bindir}/zig-0.15"
    elif [ -x "%{_bindir}/zig" ]; then
        ZIG_BIN="%{_bindir}/zig"
    else
        echo "ERROR: zig compiler not found in %{_bindir}"
        exit 1
    fi
    DESTDIR=%{_builddir}/ghostty-buildroot "$ZIG_BIN" build install \
        --summary all \
        --prefix "%{_prefix}" \
        -Dversion-string=%{version}-%{release} \
        -Doptimize=ReleaseFast \
        -Dcpu=baseline \
        -Dpie=true \
        -Demit-docs=false
fi

%install
# Copy pre-built files from build phase
cp -a %{_builddir}/ghostty-buildroot/* %{buildroot}/
rm -f %{buildroot}%{_datadir}/terminfo/g/ghostty

# Normalize systemd user unit location for robust packaging across upstream variations.
SYSTEMD_SERVICE_DEST="%{buildroot}%{ghostty_systemd_user_unitdir}/app-com.mitchellh.ghostty.service"
mkdir -p "%{buildroot}%{ghostty_systemd_user_unitdir}"
if [ ! -f "$SYSTEMD_SERVICE_DEST" ]; then
    for candidate in \
        "%{buildroot}%{_prefix}/lib/systemd/user/app-com.mitchellh.ghostty.service" \
        "%{buildroot}%{_datadir}/systemd/user/app-com.mitchellh.ghostty.service" \
        "%{buildroot}%{_prefix}/share/systemd/user/app-com.mitchellh.ghostty.service" \
        "%{buildroot}%{_prefix}/lib/systemd/user/com.mitchellh.ghostty.service" \
        "%{buildroot}%{_datadir}/systemd/user/com.mitchellh.ghostty.service" \
        "%{buildroot}%{_prefix}/share/systemd/user/com.mitchellh.ghostty.service"
    do
        if [ -f "$candidate" ]; then
            cp -a "$candidate" "$SYSTEMD_SERVICE_DEST"
            break
        fi
    done
fi
if [ ! -f "$SYSTEMD_SERVICE_DEST" ]; then
    echo "ERROR: Ghostty systemd user service was not generated by zig build."
    echo "Looked for app/com variants in %{_prefix}/lib, %{_datadir}, and share locations."
    exit 1
fi

# Normalize pkgconfig location. Fedora upstream now emits the file under /usr/share/pkgconfig.
mkdir -p %{buildroot}%{_datadir}/pkgconfig
PKGCONFIG_DEST="%{buildroot}%{_datadir}/pkgconfig/libghostty-vt.pc"
for candidate in \
    "%{buildroot}%{ghostty_libdir}/pkgconfig/libghostty-vt.pc" \
    "%{buildroot}%{_libdir}/pkgconfig/libghostty-vt.pc" \
    "%{buildroot}%{_datadir}/pkgconfig/libghostty-vt.pc"
do
    if [ -f "$candidate" ]; then
        if [ "$candidate" != "$PKGCONFIG_DEST" ]; then
            cp -a "$candidate" "$PKGCONFIG_DEST"
        fi
        break
    fi
done
rm -f %{buildroot}%{_libdir}/pkgconfig/libghostty-vt.pc

# Build include dir list for ghostty-devel to avoid "directories not owned" (es_BO/ko_KR-style issues).
INCLUDE_DIRS_FILE="%{_builddir}/ghostty-devel.include-dirs"
: > "$INCLUDE_DIRS_FILE"
if [ -d "%{buildroot}%{_includedir}/ghostty" ]; then
    find "%{buildroot}%{_includedir}/ghostty" -type d -print \
        | sed "s#^%{buildroot}##" \
        | while read -r d; do echo "%%dir $d"; done \
        >> "$INCLUDE_DIRS_FILE"
fi

# Build locale file list from actual outputs to avoid packaging errors on missing dirs.
# Use -mindepth 1 so parent locale dirs (es_BO, ko_KR, etc.) are owned
LOCALE_FILES_FILE="%{_builddir}/ghostty.locale.files"
: > "$LOCALE_FILES_FILE"
if [ -d "%{buildroot}%{_datadir}/locale" ]; then
    {
        find "%{buildroot}%{_datadir}/locale" -type f -name "com.mitchellh.ghostty.mo" -print
        find "%{buildroot}%{_datadir}/locale" -mindepth 1 -type d -print
    } | sed "s#^%{buildroot}##" | sort -u >> "$LOCALE_FILES_FILE"
fi

if [ -f "%{buildroot}%{_datadir}/kio/servicemenus/com.mitchellh.ghostty.desktop" ]; then
    chmod -x "%{buildroot}%{_datadir}/kio/servicemenus/com.mitchellh.ghostty.desktop"
fi

%files -f %{_builddir}/ghostty.locale.files
%license LICENSE
%{_bindir}/ghostty

# Desktop integration
%{_datadir}/applications/com.mitchellh.ghostty.desktop
%{_datadir}/metainfo/com.mitchellh.ghostty.metainfo.xml

# Shell completions
%{_datadir}/bash-completion/completions/ghostty.bash
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/ghostty.fish
%{_datadir}/zsh/site-functions/_ghostty

# Syntax highlighting
%dir %{_datadir}/bat
%dir %{_datadir}/bat/syntaxes
%{_datadir}/bat/syntaxes/ghostty.sublime-syntax

# Application data
%{_datadir}/ghostty

# Icons
%{_datadir}/icons/hicolor/1024x1024/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/128x128/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/128x128@2/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/16x16/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/16x16@2/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/256x256/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/256x256@2/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/32x32/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/32x32@2/apps/com.mitchellh.ghostty.png
%{_datadir}/icons/hicolor/512x512/apps/com.mitchellh.ghostty.png

# KIO integration
%dir %{_datadir}/kio
%dir %{_datadir}/kio/servicemenus
%{_datadir}/kio/servicemenus/com.mitchellh.ghostty.desktop

# Nautilus integration
%dir %{_datadir}/nautilus-python
%dir %{_datadir}/nautilus-python/extensions
%{_datadir}/nautilus-python/extensions/ghostty.py

# Neovim support
%dir %{_datadir}/nvim
%dir %{_datadir}/nvim/site
%dir %{_datadir}/nvim/site/compiler
%dir %{_datadir}/nvim/site/ftdetect
%dir %{_datadir}/nvim/site/ftplugin
%dir %{_datadir}/nvim/site/syntax
%{_datadir}/nvim/site/compiler/ghostty.vim
%{_datadir}/nvim/site/ftdetect/ghostty.vim
%{_datadir}/nvim/site/ftplugin/ghostty.vim
%{_datadir}/nvim/site/syntax/ghostty.vim

# Vim support
%dir %{_datadir}/vim
%dir %{_datadir}/vim/vimfiles
%dir %{_datadir}/vim/vimfiles/compiler
%dir %{_datadir}/vim/vimfiles/ftdetect
%dir %{_datadir}/vim/vimfiles/ftplugin
%dir %{_datadir}/vim/vimfiles/syntax
%{_datadir}/vim/vimfiles/compiler/ghostty.vim
%{_datadir}/vim/vimfiles/ftdetect/ghostty.vim
%{_datadir}/vim/vimfiles/ftplugin/ghostty.vim
%{_datadir}/vim/vimfiles/syntax/ghostty.vim

# D-Bus service
%{_datadir}/dbus-1/services/com.mitchellh.ghostty.service

# Systemd user service
%dir %{ghostty_systemd_user_unitdir}
%{ghostty_systemd_user_unitdir}/app-com.mitchellh.ghostty.service

# Terminfo
%{_datadir}/terminfo/x/xterm-ghostty

%package devel
Summary:        Ghostty VT library development files
Requires:       %{name} = %{version}-%{release}
Provides:       pkgconfig(libghostty-vt) = 0.1.0

%description devel
This package contains the headers and pkg-config metadata for the Ghostty VT library.

%files devel -f %{_builddir}/ghostty-devel.include-dirs
%{_includedir}/ghostty/vt.h
%{_includedir}/ghostty/vt/*.h
%{_includedir}/ghostty/vt/key/encoder.h
%{_includedir}/ghostty/vt/key/event.h
%{ghostty_libdir}/libghostty-vt.so
%{ghostty_libdir}/libghostty-vt.so.0
%{ghostty_libdir}/libghostty-vt.so.0.1.0
%{_datadir}/pkgconfig/libghostty-vt.pc

%changelog
* Sat Jan 10 2026 Avenge Media <AvengeMedia.US@gmail.com> - 1.2.3-1
- Initial OpenSUSE package using distro toolchain Zig
- GPU-accelerated terminal emulator with platform-native UI
- Uses Zig %{zig_minimum_version}+ for build compatibility with modern Ghostty releases
