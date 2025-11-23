Name:           quickshell-git
Version:        0.2.1+git
Release:        1%{?dist}
Summary:        Flexible toolkit for creating desktop shells using QtQuick (git)

License:        LGPL-3.0
URL:            https://github.com/quickshell-mirror/quickshell
Source0:        quickshell-source.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja
BuildRequires:  gcc-c++
BuildRequires:  git
BuildRequires:  qt6-base-devel
BuildRequires:  qt6-declarative-devel
BuildRequires:  qt6-declarative-private-devel
BuildRequires:  qt6-wayland-devel
BuildRequires:  qt6-waylandclient-private-devel
BuildRequires:  qt6-tools-devel
BuildRequires:  qt6-svg-devel
BuildRequires:  qt6-shadertools-devel
BuildRequires:  cli11-devel
BuildRequires:  wayland-protocols-devel
BuildRequires:  wayland-devel
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pam-devel
BuildRequires:  pipewire-devel
BuildRequires:  libdrm-devel
BuildRequires:  libgbm-devel
BuildRequires:  Mesa-libEGL-devel
BuildRequires:  Mesa-libGLESv3-devel
BuildRequires:  polkit-devel
BuildRequires:  jemalloc-devel
BuildRequires:  chrpath
Requires:       qt6-wayland
Requires:       libQt6Svg6
Requires:       jemalloc
Provides:       quickshell
Conflicts:      quickshell

%description
Quickshell is a flexible toolkit for creating desktop shells using QtQuick.
This git version is built from the latest source and includes full feature
set including wayland, layer-shell, session-lock, toplevel-management,
screencopy, pipewire, tray, mpris, and compositor support.

%prep
%setup -q -n quickshell-source

%build
if [ -f "src/wayland/CMakeLists.txt" ]; then
    if ! pkg-config --atleast-version=1.41 wayland-protocols 2>/dev/null; then
        WL_VERSION=$(pkg-config --modversion wayland-protocols 2>/dev/null || echo "unknown")
        sed -i 's/wayland-protocols>=1\.41/wayland-protocols>=1.38/g' src/wayland/CMakeLists.txt
        echo "Patched wayland-protocols requirement from 1.41 to 1.38 (system has $WL_VERSION)"
    else
        echo "wayland-protocols >= 1.41 available, no patch needed"
    fi
fi

export PKG_CONFIG_PATH="/usr/lib64/pkgconfig:/usr/share/pkgconfig"
export CFLAGS="-I/usr/include/wayland"
export CXXFLAGS="-I/usr/include/wayland"
rm -rf build
mkdir -p build
cd build
cmake -GNinja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCRASH_REPORTER=off \
    -DCMAKE_CXX_STANDARD=20 \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_RPATH="" \
    -DCMAKE_BUILD_RPATH="" \
    ..

cmake --build .
cd ..

%install
cd build
DESTDIR=%{buildroot} cmake --install .
cd ..

chrpath -d %{buildroot}%{_bindir}/quickshell 2>/dev/null || true

%files
%license LICENSE
%doc README.md
%{_bindir}/quickshell
%{_bindir}/qs
%{_datadir}/applications/org.quickshell.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/scalable/apps/org.quickshell.svg

%changelog
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.2.1+git-1
- Initial OBS package (nightly builds)
