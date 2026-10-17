%if 0%{?el10}
%global debug_package %{nil}
%endif

Name:           xwayland-satellite
Version:        0.8.3
Release:        1%{?dist}
Summary:        Xwayland outside your Wayland compositor

License:        MPL-2.0
URL:            https://github.com/Supreeeme/xwayland-satellite
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/xwayland-satellite-%{version}.tar.gz

BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  clang-devel
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(wayland-cursor)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-cursor)
BuildRequires:  pkgconfig(fontconfig)
BuildRequires:  systemd-rpm-macros

Requires:       xorg-x11-server-Xwayland

Conflicts:      xwayland-satellite-git

%description
xwayland-satellite grants rootless Xwayland integration to any Wayland
compositor implementing xdg_wm_base and viewporter.

%prep
%autosetup -n xwayland-satellite-%{version}
sed -i 's|/usr/local/bin/xwayland-satellite|%{_bindir}/xwayland-satellite|' resources/xwayland-satellite.service

%build
# The shipped unit is Type=notify, which needs the systemd feature
cargo build --release --features systemd,fontconfig

%install
install -Dm755 target/release/xwayland-satellite %{buildroot}%{_bindir}/xwayland-satellite
install -Dm644 resources/xwayland-satellite.service %{buildroot}%{_userunitdir}/xwayland-satellite.service

%post
%systemd_user_post xwayland-satellite.service

%preun
%systemd_user_preun xwayland-satellite.service

%postun
%systemd_user_postun xwayland-satellite.service

%files
%license LICENSE
%doc README.md
%{_bindir}/xwayland-satellite
%{_userunitdir}/xwayland-satellite.service

%changelog
* Fri Oct 16 2026 Purian23 <purian23@users.noreply.github.com> - 0.8.3-1
- Initial Copr package release for EL10
- Version 0.8.3
