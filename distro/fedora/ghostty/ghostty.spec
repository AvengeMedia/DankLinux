%global zig_version 0.14.0

%ifarch x86_64
%global zig_arch x86_64
%endif
%ifarch aarch64
%global zig_arch aarch64
%endif

%global _missing_build_ids_terminate_build 0
%global debug_package %{nil}

Name:           ghostty
Version:        1.2.3
Release:        1%{?dist}
Summary:        Fast, feature-rich, and cross-platform terminal emulator that uses platform-native UI and GPU acceleration

License:        MIT
URL:            https://github.com/ghostty-org/ghostty
Source0:        https://github.com/ghostty-org/ghostty/archive/refs/tags/v%{version}.tar.gz
Source1:        https://ziglang.org/download/%{zig_version}/zig-linux-x86_64-%{zig_version}.tar.xz
Source2:        https://ziglang.org/download/%{zig_version}/zig-linux-aarch64-%{zig_version}.tar.xz

ExclusiveArch: x86_64 aarch64

BuildRequires: blueprint-compiler
BuildRequires: fontconfig-devel
BuildRequires: freetype-devel
BuildRequires: glib2-devel
BuildRequires: gtk4-devel
BuildRequires: gtk4-layer-shell-devel
BuildRequires: harfbuzz-devel
BuildRequires: libadwaita-devel
BuildRequires: libpng-devel
BuildRequires: oniguruma-devel
BuildRequires: pixman-devel
BuildRequires: pkg-config
BuildRequires: wayland-protocols-devel
BuildRequires: zlib-ng-devel

Requires: fontconfig
Requires: freetype
Requires: glib2
Requires: gtk4
Requires: harfbuzz
Requires: libadwaita
Requires: libpng
Requires: oniguruma
Requires: pixman
Requires: zlib-ng

%description
%{summary}.

%prep
%setup -q -n ghostty-%{version}

curl -L --fail --retry 3 --retry-delay 5 -o ghostty-themes.tgz \
    "https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/release-20251201-150531-bfb3ee1/ghostty-themes.tgz"
THEMES_FILE="file://$PWD/ghostty-themes.tgz"
sed -i "s|https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/.\+/ghostty-themes.tgz|${THEMES_FILE}|" build.zig.zon
sed -i '/\.iterm2_themes/,/}/ s|\.hash = "[^"]\+"|.hash = "N-V-__8AANFEAwCzzNzNs3Gaq8pzGNl2BbeyFBwTyO5iZJL-"|' build.zig.zon

# Use upstream Zig 0.14.0 binarys to avoid Fedora 43+ Zig 0.15 build breakage
%ifarch x86_64
tar -xf %{SOURCE1}
%endif
%ifarch aarch64
tar -xf %{SOURCE2}
%endif

ZIG_BIN="$PWD/zig-linux-%{zig_arch}-%{zig_version}/zig"

%build

%install
ZIG_BIN="$PWD/zig-linux-%{zig_arch}-%{zig_version}/zig"

DESTDIR=%{buildroot} "$ZIG_BIN" build \
    --summary all \
    --prefix "%{_prefix}" \
    -Dversion-string=%{version}-%{release} \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline \
    -Dpie=true

%if 0%{?fedora} >= 42
rm -f "%{buildroot}%{_prefix}/share/terminfo/g/ghostty"
%endif

%files
%license LICENSE
%{_bindir}/ghostty
%{_prefix}/share/applications/com.mitchellh.ghostty.desktop
%{_prefix}/share/bash-completion/completions/ghostty.bash
%{_prefix}/share/bat/syntaxes/ghostty.sublime-syntax
%{_prefix}/share/fish/vendor_completions.d/ghostty.fish
%{_prefix}/share/ghostty
%{_prefix}/share/icons/hicolor/1024x1024/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/128x128/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/128x128@2/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/16x16/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/16x16@2/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/256x256/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/256x256@2/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/32x32/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/32x32@2/apps/com.mitchellh.ghostty.png
%{_prefix}/share/icons/hicolor/512x512/apps/com.mitchellh.ghostty.png
%{_prefix}/share/kio/servicemenus/com.mitchellh.ghostty.desktop
%{_prefix}/share/nautilus-python/extensions/ghostty.py
%{_prefix}/share/nvim/site/compiler/ghostty.vim
%{_prefix}/share/nvim/site/ftdetect/ghostty.vim
%{_prefix}/share/nvim/site/ftplugin/ghostty.vim
%{_prefix}/share/nvim/site/syntax/ghostty.vim
%{_prefix}/share/vim/vimfiles/compiler/ghostty.vim
%{_prefix}/share/vim/vimfiles/ftdetect/ghostty.vim
%{_prefix}/share/vim/vimfiles/ftplugin/ghostty.vim
%{_prefix}/share/vim/vimfiles/syntax/ghostty.vim
%{_prefix}/share/zsh/site-functions/_ghostty
%{_prefix}/share/dbus-1/services/com.mitchellh.ghostty.service
%{_prefix}/share/locale/*/LC_MESSAGES/com.mitchellh.ghostty.mo
%{_prefix}/share/metainfo/com.mitchellh.ghostty.metainfo.xml
%{_prefix}/share/systemd/user/app-com.mitchellh.ghostty.service

%{_prefix}/share/terminfo/x/xterm-ghostty
%if 0%{?fedora} < 42
    %{_prefix}/share/terminfo/g/ghostty
%endif

%changelog
%autochangelog
