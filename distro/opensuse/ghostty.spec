Name:           ghostty
Version:        1.2.3
Release:        1%{?dist}
Summary:        Fast, feature-rich, and cross-platform terminal emulator that uses platform-native UI and GPU acceleration

License:        MIT
URL:            https://github.com/ghostty-org/ghostty
Source0:        ghostty-%{version}.tar.xz

BuildRequires:  zig14
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

# Themes are already included in source tarball
THEMES_FILE="file://$PWD/ghostty-themes.tgz"
sed -i "s|https://github.com/mbadolato/iTerm2-Color-Schemes/releases/download/.\+/ghostty-themes.tgz|${THEMES_FILE}|" build.zig.zon
sed -i '/\.iterm2_themes/,/}/ s|\.hash = "[^"]\+"|.hash = "N-V-__8AANFEAwCzzNzNs3Gaq8pzGNl2BbeyFBwTyO5iZJL-"|' build.zig.zon

# Wayland dependencies included in source tarball
sed -i "s|https://deps.files.ghostty.org/wayland-9cb3d7aa9dc995ffafdbdef7ab86a949d0fb0e7d.tar.gz|file://$PWD/wayland.tar.gz|" build.zig.zon
sed -i "s|https://deps.files.ghostty.org/wayland-protocols-258d8f88f2c8c25a830c6316f87d23ce1a0f12d9.tar.gz|file://$PWD/wayland-protocols.tar.gz|" build.zig.zon
sed -i "s|https://deps.files.ghostty.org/plasma_wayland_protocols-12207e0851c12acdeee0991e893e0132fc87bb763969a585dc16ecca33e88334c566.tar.gz|file://$PWD/plasma_wayland_protocols.tar.gz|" build.zig.zon

%build
# zig14 package provides /usr/bin/zig-0.14
# Use vendored Zig dependencies from source tarball
export ZIG_GLOBAL_CACHE_DIR=$PWD/zig-deps
# Build with temp DESTDIR to prevent writing to system directories
mkdir -p %{_builddir}/ghostty-buildroot
DESTDIR=%{_builddir}/ghostty-buildroot /usr/bin/zig-0.14 build \
    --summary new \
    --prefix "%{_prefix}" \
    -Dversion-string=%{version}-%{release} \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline \
    -Dpie=true

%install
export ZIG_GLOBAL_CACHE_DIR=$PWD/zig-deps
DESTDIR=%{buildroot} /usr/bin/zig-0.14 build install \
    --prefix "%{_prefix}" \
    -Doptimize=ReleaseFast \
    -Dcpu=baseline

%files
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
%dir %{_datadir}/systemd
%dir %{_datadir}/systemd/user
%{_datadir}/systemd/user/app-com.mitchellh.ghostty.service

# Translations
%dir %{_datadir}/locale/bg_BG.UTF-8
%dir %{_datadir}/locale/bg_BG.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/ca_ES.UTF-8
%dir %{_datadir}/locale/ca_ES.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/de_DE.UTF-8
%dir %{_datadir}/locale/de_DE.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/es_AR.UTF-8
%dir %{_datadir}/locale/es_AR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/es_BO.UTF-8
%dir %{_datadir}/locale/es_BO.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/fr_FR.UTF-8
%dir %{_datadir}/locale/fr_FR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/ga_IE.UTF-8
%dir %{_datadir}/locale/ga_IE.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/he_IL.UTF-8
%dir %{_datadir}/locale/he_IL.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/hr_HR.UTF-8
%dir %{_datadir}/locale/hr_HR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/hu_HU.UTF-8
%dir %{_datadir}/locale/hu_HU.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/id_ID.UTF-8
%dir %{_datadir}/locale/id_ID.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/it_IT.UTF-8
%dir %{_datadir}/locale/it_IT.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/ja_JP.UTF-8
%dir %{_datadir}/locale/ja_JP.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/ko_KR.UTF-8
%dir %{_datadir}/locale/ko_KR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/mk_MK.UTF-8
%dir %{_datadir}/locale/mk_MK.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/nb_NO.UTF-8
%dir %{_datadir}/locale/nb_NO.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/nl_NL.UTF-8
%dir %{_datadir}/locale/nl_NL.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/pl_PL.UTF-8
%dir %{_datadir}/locale/pl_PL.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/pt_BR.UTF-8
%dir %{_datadir}/locale/pt_BR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/ru_RU.UTF-8
%dir %{_datadir}/locale/ru_RU.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/tr_TR.UTF-8
%dir %{_datadir}/locale/tr_TR.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/uk_UA.UTF-8
%dir %{_datadir}/locale/uk_UA.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/zh_CN.UTF-8
%dir %{_datadir}/locale/zh_CN.UTF-8/LC_MESSAGES
%dir %{_datadir}/locale/zh_TW.UTF-8
%dir %{_datadir}/locale/zh_TW.UTF-8/LC_MESSAGES
%{_datadir}/locale/*/LC_MESSAGES/com.mitchellh.ghostty.mo

# Terminfo
%{_datadir}/terminfo/x/xterm-ghostty
%{_datadir}/terminfo/g/ghostty

%changelog
* Sat Jan 10 2026 Avenge Media <AvengeMedia.US@gmail.com> - 1.2.3-1
- Initial OpenSUSE package using zig14 from danklinux repository
- GPU-accelerated terminal emulator with platform-native UI
- Uses /usr/bin/zig-0.14 from zig14 package
