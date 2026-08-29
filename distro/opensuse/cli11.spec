%global debug_package %{nil}

Name:           cli11
Version:        2.7.2
Release:        2%{?dist}
Summary:        Command line parser for C++11

License:        BSD-3-Clause
URL:            https://github.com/CLIUtils/CLI11
Source0:        %{url}/archive/v%{version}/CLI11-%{version}.tar.gz

BuildRequires:  cmake >= 3.5
BuildRequires:  gcc-c++
# Keep this archful on OBS. noarch RPMs from x86_64 vs aarch64 workers
# are not identical, and the scheduler then blocks dependents forever.

%description
CLI11 is a command line parser for C++11 and beyond that provides a
rich feature set with a simple and intuitive interface.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}
Provides:       %{name}-static = %{version}-%{release}

%description devel
Header-only CLI11 development files (includes, CMake config, pkg-config).

%prep
%setup -q -n CLI11-%{version}

%build
mkdir -p build
cd build
cmake \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCLI11_BUILD_DOCS:BOOL=FALSE \
    -DCLI11_BUILD_TESTS:BOOL=FALSE \
    -DCLI11_CXX_STANDARD=17 \
    ..

%install
cd build
DESTDIR=%{buildroot} cmake --install .

%files
%license LICENSE
%doc README.md

%files devel
%{_includedir}/CLI/
%{_datadir}/cmake/CLI11/
%{_datadir}/pkgconfig/CLI11.pc

%changelog
* Sat Aug 29 2026 Avenge Media <AvengeMedia.US@gmail.com> - 2.7.2-2
- Build per-arch so OBS does not block aarch64 dependents on mismatched noarch RPMs

* Sat Aug 29 2026 Avenge Media <AvengeMedia.US@gmail.com> - 2.7.2-1
- Initial OBS package so Leap 16.1 can resolve cli11-devel
