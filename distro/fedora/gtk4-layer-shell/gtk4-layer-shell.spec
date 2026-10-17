%bcond_with check

Name:           gtk4-layer-shell
Version:        1.3.0
Release:        1%{?dist}
Summary:        Library to create panels and other desktop components for Wayland

License:        MIT
URL:            https://github.com/wmww/gtk4-layer-shell
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  vala
BuildRequires:  pkgconfig(gobject-introspection-1.0)
BuildRequires:  pkgconfig(gtk4)
BuildRequires:  pkgconfig(wayland-client) >= 1.10.0
BuildRequires:  pkgconfig(wayland-protocols) >= 1.16
BuildRequires:  pkgconfig(wayland-scanner) >= 1.10.0
BuildRequires:  pkgconfig(wayland-server) >= 1.10.0
%if %{with check}
BuildRequires:  python3-gobject
%endif

%description
A library for using the Layer Shell and Session Lock Wayland protocols with
GTK4. This Library is compatible with C, C++ and any language that supports
GObject introspection files (Python, Vala, etc).

The Layer Shell protocol allows building desktop shell components such as
panels, notifications and wallpapers. It can be used to anchor your windows to a
corner or edge of the output, or stretch them across the entire output.

The Session Lock protocol allows building lock screens.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description    devel
Development files for %{name}.

%prep
%autosetup

%build
# Smoke tests need a GTK4-capable lua-lgi, which no distro ships
%meson \
    %if %{with check}
    -Dsmoke-tests=false \
    -Dtests=true \
    %endif
    %{nil}
%meson_build

%install
%meson_install

%if %{with check}
%check
%meson_test
%endif

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_libdir}/girepository-1.0/Gtk4LayerShell-*.typelib
%{_libdir}/girepository-1.0/Gtk4SessionLock-*.typelib
%{_libdir}/lib%{name}.so.%{version}
%{_libdir}/lib%{name}.so.0

%files devel
%{_datadir}/gir-1.0/Gtk4LayerShell-*.gir
%{_datadir}/gir-1.0/Gtk4SessionLock-*.gir
%{_datadir}/vala/vapi/%{name}-*
%{_includedir}/%{name}/
%{_libdir}/lib%{name}.so
%{_libdir}/liblayer-shell-preload.so
%{_libdir}/pkgconfig/*.pc

%changelog
* Fri Oct 16 2026 Purian23 <purian23@users.noreply.github.com> - 1.3.0-1
- Initial Copr package release for EL10
- Version 1.3.0
