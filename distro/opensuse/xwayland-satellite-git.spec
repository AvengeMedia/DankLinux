Name:           xwayland-satellite-git
Version:        0.8+git205.1b918e29
Release:        1%{?dist}
Summary:        Rootless Xwayland integration for Wayland compositors (git)

License:        MPL-2.0
URL:            https://github.com/Supreeeme/xwayland-satellite
Source0:        xwayland-satellite-source.tar.gz

BuildRequires:  cargo >= 1.83
BuildRequires:  rust >= 1.83
BuildRequires:  clang-devel
BuildRequires:  pkgconfig
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-composite)
BuildRequires:  pkgconfig(xcb-randr)
BuildRequires:  pkgconfig(xcb-res)
BuildRequires:  pkgconfig(xcb-cursor)
Provides:       xwayland-satellite
Conflicts:      xwayland-satellite

%description
xwayland-satellite grants rootless Xwayland integration to any Wayland
compositor implementing xdg_wm_base and viewporter. This is particularly
useful for compositors that do not want to implement support for rootless
Xwayland themselves, such as niri.

This is the git/development version with the latest features.
For stable releases, use the 'xwayland-satellite' package instead.

%prep
%setup -q -n xwayland-satellite-source

%build
# Fix vendor checksums for offline build
for checksum in vendor/*/.cargo-checksum.json; do
    if [ -f "$checksum" ]; then
        pkg=$(cat "$checksum" | grep -o '"package":"[^"]*"' | cut -d'"' -f4)
        echo "{\"files\":{},\"package\":\"$pkg\"}" > "$checksum"
    fi
done

cargo build --offline --release

%install
install -Dm755 target/release/xwayland-satellite %{buildroot}%{_bindir}/xwayland-satellite

%files
%license LICENSE
%doc README.md
%{_bindir}/xwayland-satellite

%changelog
* Sat Dec 06 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.8+git205.1b918e29-1
- Git snapshot (commit 205: 1b918e29)
* Tue Nov 25 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.7+git-1
- Initial git package

