%if 0%{?el10}
%global debug_package %{nil}
%endif

Name:           alacritty
Version:        0.17.0
Release:        1%{?dist}
Summary:        A cross-platform, GPU-accelerated terminal emulator

License:        Apache-2.0
URL:            https://github.com/alacritty/alacritty
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/alacritty-%{version}.tar.gz

BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  python3
BuildRequires:  pkgconfig(fontconfig)
BuildRequires:  pkgconfig(freetype2)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  desktop-file-utils

Requires:       hicolor-icon-theme
# ncurses-base ships the alacritty terminfo entry
Requires:       ncurses-base

%description
Alacritty is a modern terminal emulator that comes with sensible defaults,
but allows for extensive configuration. By integrating with other
applications, rather than reimplementing their functionality, it manages
to provide a flexible set of features while remaining resource efficient.

%prep
%autosetup -n alacritty-%{version}

%build
cargo build --release

%install
install -Dm755 target/release/alacritty %{buildroot}%{_bindir}/alacritty
install -Dm644 extra/linux/Alacritty.desktop \
    %{buildroot}%{_datadir}/applications/Alacritty.desktop
install -Dm644 extra/linux/org.alacritty.Alacritty.appdata.xml \
    %{buildroot}%{_metainfodir}/org.alacritty.Alacritty.appdata.xml
install -Dm644 extra/logo/alacritty-term.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/Alacritty.svg
install -Dm644 extra/completions/alacritty.bash \
    %{buildroot}%{_datadir}/bash-completion/completions/alacritty
install -Dm644 extra/completions/_alacritty \
    %{buildroot}%{_datadir}/zsh/site-functions/_alacritty
install -Dm644 extra/completions/alacritty.fish \
    %{buildroot}%{_datadir}/fish/vendor_completions.d/alacritty.fish
desktop-file-validate %{buildroot}%{_datadir}/applications/Alacritty.desktop

%files
%license LICENSE-APACHE
%doc README.md
%{_bindir}/alacritty
%{_datadir}/applications/Alacritty.desktop
%{_metainfodir}/org.alacritty.Alacritty.appdata.xml
%{_datadir}/icons/hicolor/scalable/apps/Alacritty.svg
%{_datadir}/bash-completion/completions/alacritty
%{_datadir}/zsh/site-functions/_alacritty
%{_datadir}/fish/vendor_completions.d/alacritty.fish

%changelog
* Fri Oct 16 2026 Purian23 <purian23@users.noreply.github.com> - 0.17.0-1
- Initial Copr package release for EL10
- Version 0.17.0
