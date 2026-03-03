Name:           cpptrace
Version:        1.0.4
Release:        3%{?dist}
Summary:        Simple, portable, and drop-in C++ stacktrace library

License:        MIT
URL:            https://github.com/jeremy-rifkin/cpptrace
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.14
BuildRequires:  gcc-c++
BuildRequires:  ninja
BuildRequires:  libdwarf-devel
BuildRequires:  libunwind-devel
BuildRequires:  pkgconf

%description
cpptrace is an easy to use C++ stacktrace library providing a 
straightforward unified interface for stack traces in C++.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}

%description    devel
The %{name}-devel package contains libraries and header files for
developing applications that use %{name}.

%prep
%autosetup -p1 -n %{name}-%{version}

%build
# openSUSE specific cmake call that matches Fedora's general structure
mkdir -p build
cd build
cmake -GNinja \
       -DCMAKE_INSTALL_PREFIX=/usr \
       -DBUILD_SHARED_LIBS=ON \
       -DCPPTRACE_USE_EXTERNAL_LIBDWARF=ON \
       -DCPPTRACE_FIND_LIBDWARF_WITH_PKGCONFIG=ON \
       -DCPPTRACE_GET_SYMBOLS_WITH_LIBDWARF=ON \
       -DCPPTRACE_UNWIND_WITH_LIBUNWIND=ON \
       ..
ninja -v

%install
cd build
DESTDIR=%{buildroot} ninja install

%files
%license LICENSE
%doc README.md
%{_libdir}/libcpptrace.so.*

%files devel
%{_includedir}/cpptrace/
%{_includedir}/ctrace/
%{_libdir}/libcpptrace.so
%{_libdir}/cmake/cpptrace/

%changelog
* Mon Mar 02 2026 Avenge Media <AvengeMedia.US@gmail.com> - 1.0.4-1
- Initial package for openSUSE
