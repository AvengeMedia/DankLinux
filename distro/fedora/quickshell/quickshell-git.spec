%bcond_with         asan

# Updated 2025-10-30: Added glib-2.0 dependency for new Polkit service
%global commit      d99d87d5e5ec4e696815348692fdaaf0b6be1b2c
%global commits     822
%global snapdate    20260610
%global tag         0.3.1
%global changelog_tag 0.3.0

Name:               quickshell-git
Version:            %{tag}^%{commits}.git%(c=%{commit}; echo ${c:0:7})
Release:            %autorelease.5
Summary:            Flexible QtQuick based desktop shell toolkit

License:            LGPL-3.0-only AND GPL-3.0-only
URL:                https://github.com/quickshell-mirror/quickshell
Source0:            %{url}/archive/%{commit}/quickshell-%{commit}.tar.gz

Conflicts:          quickshell <= %{tag}

%if 0%{?fedora}
%global crash_handler ON
BuildRequires:      cpptrace-devel
BuildRequires:      libdwarf-devel
BuildRequires:      pkgconfig(libzstd)
%else
%global crash_handler OFF
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
        -DCRASH_HANDLER=%{crash_handler} \
        -DUSE_JEMALLOC=%{jemalloc_enabled} \
        -DCMAKE_BUILD_TYPE=Release \
        -DDISTRIBUTOR="Fedora COPR (avengemedia/quickshell)" \
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
%doc changelog/v%{changelog_tag}.md
%{_bindir}/qs
%{_bindir}/quickshell
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.quickshell.svg
%{_libdir}/qt6/qml/Quickshell

%changelog
* Tue May 05 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 0.3.1^815.git59e9c47-1.5
- ci: COPR rebuild bump (workflow)

* Tue May 05 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 0.3.1^815.git59e9c47-1.4
- ci: COPR rebuild bump (workflow)

* Tue May 05 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 0.3.1^815.git59e9c47-1.3
- ci: COPR rebuild bump (workflow)

* Tue May 05 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 0.3.1^815.git59e9c47-1.2
- ci: COPR rebuild bump (workflow)

* Tue May 05 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 0.3.1^815.git59e9c47-1.1
- ci: COPR rebuild bump (workflow)

%autochangelog
