%bcond_with         asan

# Updated 2025-10-30: Added glib-2.0 dependency for new Polkit service
%global commit      1e4d804e7f3fa7465811030e8da2bf10d544426a
%global commits     732
%global snapdate    20260128
%global tag         0.2.1

Name:               quickshell-git
Version:            %{tag}^%{commits}.git%(c=%{commit}; echo ${c:0:7})
Release:            %autorelease
Summary:            Flexible QtQuick based desktop shell toolkit

License:            LGPL-3.0-only AND GPL-3.0-only
URL:                https://github.com/quickshell-mirror/quickshell
Source0:            %{url}/archive/%{commit}/quickshell-%{commit}.tar.gz

Conflicts:          quickshell <= %{tag}

%if 0%{?fedora}
%global crash_reporter ON
BuildRequires:      breakpad-static
%else
%global crash_reporter OFF
%endif

%if 0%{?fedora}
%global jemalloc_enabled ON
%else
%global jemalloc_enabled OFF
%endif
BuildRequires:      cmake
BuildRequires:      cmake(Qt6Core)
BuildRequires:      cmake(Qt6Qml)
BuildRequires:      cmake(Qt6ShaderTools)
BuildRequires:      cmake(Qt6WaylandClient)
BuildRequires:      gcc-c++
BuildRequires:      ninja-build
%if 0%{?fedora}
BuildRequires:      pkgconfig(breakpad)
BuildRequires:      pkgconfig(CLI11)
%else
BuildRequires:      cli11-devel
%endif
BuildRequires:      pkgconfig(gbm)
BuildRequires:      pkgconfig(glib-2.0)
BuildRequires:      pkgconfig(polkit-agent-1)
%if 0%{?fedora}
BuildRequires:      pkgconfig(jemalloc)
%endif
BuildRequires:      pkgconfig(libdrm)
BuildRequires:      pkgconfig(libpipewire-0.3)
BuildRequires:      pkgconfig(pam)
BuildRequires:      pkgconfig(wayland-client)
BuildRequires:      pkgconfig(wayland-protocols)
BuildRequires:      qt6-qtbase-private-devel
BuildRequires:      spirv-tools

%if %{with asan}
BuildRequires:      libasan
%endif

Provides:           desktop-notification-daemon

%description
Flexible toolkit for making desktop shells with QtQuick, targeting
Wayland and X11.

%prep
%autosetup -n quickshell-%{commit} -p1

%build
%cmake  -GNinja \
%if %{with asan}
        -DASAN=ON \
%endif
        -DBUILD_SHARED_LIBS=OFF \
        -DCRASH_REPORTER=%{crash_reporter} \
        -DUSE_JEMALLOC=%{jemalloc_enabled} \
        -DCMAKE_BUILD_TYPE=Release \
        -DDISTRIBUTOR="Fedora COPR (avengemedia/quickshell)" \
        -DDISTRIBUTOR_DEBUGINFO_AVAILABLE=YES \
        -DGIT_REVISION=%{commit} \
        -DINSTALL_QML_PREFIX=%{_lib}/qt6/qml
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%license LICENSE-GPL
%doc BUILD.md
%doc CONTRIBUTING.md
%doc README.md
%doc changelog/v%{tag}.md
%{_bindir}/qs
%{_bindir}/quickshell
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.quickshell.svg
%{_libdir}/qt6/qml/Quickshell

%changelog
%autochangelog
