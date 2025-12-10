Name:           niri-git
Version:        25.11+git2570.4d058e61
Release:        1%{?dist}
Epoch:          1
Summary:        Scrollable-tiling Wayland compositor (nightly)

License:        GPL-3.0
URL:            https://github.com/YaLTeR/niri
Source0:        niri.tar

BuildRequires:  cargo >= 1.80.1
BuildRequires:  rust >= 1.80.1
BuildRequires:  clang-devel
BuildRequires:  pkgconfig
BuildRequires:  wayland-devel
BuildRequires:  pkgconfig(cairo-gobject)
BuildRequires:  pkgconfig(dbus-1)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(libdisplay-info)
BuildRequires:  pkgconfig(libinput)
BuildRequires:  pkgconfig(libseat)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(udev)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pango-devel
BuildRequires:  pipewire-devel
BuildRequires:  libdisplay-info-devel

Recommends:     alacritty
Recommends:     fuzzel
Recommends:     xdg-desktop-portal-gtk
Recommends:     xdg-desktop-portal-gnome
Recommends:     gnome-keyring
Recommends:     xwayland-satellite-git

Conflicts:      niri
Provides:       niri

%description
niri is a scrollable-tiling Wayland compositor. It provides a unique
scrollable tiling layout that allows for infinite workspace scrolling.

This is the nightly/git version with the latest development features.
For stable releases, use the 'niri' package instead.

%prep
%setup -q -n niri

%build
for checksum in vendor/*/.cargo-checksum.json; do
    if [ -f "$checksum" ]; then
        pkg=$(cat "$checksum" | grep -o '"package":"[^"]*"' | cut -d'"' -f4)
        echo "{\"files\":{},\"package\":\"$pkg\"}" > "$checksum"
    fi
done

cargo build --offline --release --features default

for shell in bash fish zsh; do
    ./target/release/niri completions $shell > $shell-completions
done

%install
install -Dm755 target/release/niri %{buildroot}%{_bindir}/niri
install -Dm755 resources/niri-session %{buildroot}%{_bindir}/niri-session
install -Dm644 resources/niri.service %{buildroot}%{_userunitdir}/niri.service
install -Dm644 resources/niri-shutdown.target %{buildroot}%{_userunitdir}/niri-shutdown.target
install -Dm644 resources/niri.desktop %{buildroot}%{_datadir}/wayland-sessions/niri.desktop
install -Dm644 resources/niri-portals.conf %{buildroot}%{_datadir}/xdg-desktop-portal/niri-portals.conf
install -Dm644 resources/default-config.kdl %{buildroot}%{_docdir}/niri-git/default-config.kdl
install -Dm644 README.md %{buildroot}%{_docdir}/niri-git/README.md
install -Dm644 bash-completions %{buildroot}%{_datadir}/bash-completion/completions/niri
install -Dm644 fish-completions %{buildroot}%{_datadir}/fish/vendor_completions.d/niri.fish
install -Dm644 zsh-completions %{buildroot}%{_datadir}/zsh/site-functions/_niri

%files
%license LICENSE
%doc README.md
%{_bindir}/niri
%{_bindir}/niri-session
%{_userunitdir}/niri.service
%{_userunitdir}/niri-shutdown.target
%dir %{_datadir}/wayland-sessions
%{_datadir}/wayland-sessions/niri.desktop
%dir %{_datadir}/xdg-desktop-portal
%{_datadir}/xdg-desktop-portal/niri-portals.conf
%{_docdir}/niri-git/
%{_datadir}/bash-completion/completions/niri
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/niri.fish
%{_datadir}/zsh/site-functions/_niri

%changelog
* Wed Dec 10 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2570.4d058e61-1
- Git snapshot (commit 2570: 4d058e61)
* Tue Dec 09 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2569.83a733e0-1
- Git snapshot (commit 2569: 83a733e0)
* Sat Dec 06 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2568.ba29735f-1
- Git snapshot (commit 2568: ba29735f)
* Tue Dec 02 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2566.f874b2fc-1
- Git snapshot (commit 2566: f874b2fc)
* Sun Nov 30 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2565.311ca6b5-1
- Git snapshot (commit 2565: 311ca6b5)
* Sat Nov 29 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.11+git2564.b35bcae3-1
- Git snapshot (commit 2564: b35bcae3)
* Fri Nov 28 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.08+git2561.0652342d-1
- Git snapshot (commit 2561: 0652342d)
* Thu Nov 27 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.08+git2560.e863f52f-1
- Git snapshot (commit 2560: e863f52f)
* Wed Nov 26 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.08+git2559.8370c539-1
- Git snapshot (commit 2559: 8370c539)
* Tue Nov 25 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.08+git2557.54c7fdcd-1
- Git snapshot (commit 2557: 54c7fdcd)
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com> - 25.08+git-1
- Initial OBS package (nightly builds)
