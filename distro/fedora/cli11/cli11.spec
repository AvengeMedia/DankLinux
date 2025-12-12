%global debug_package %{nil}
%global _docdir_fmt %{name}-devel

Name:           cli11
Version:        2.6.1
Release:        1%{?dist}
Summary:        Command line parser for C++11

License:        BSD-3-Clause
URL:            https://github.com/CLIUtils/CLI11
Source:         %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.5
BuildRequires:  gcc-c++

%description
CLI11 is a command line parser for C++11 and beyond that provides a
rich feature set with a simple and intuitive interface.

%package devel
Summary:        Command line parser for C++11
BuildArch:      noarch
Provides:       %{name}-static = %{version}-%{release}

%description devel
CLI11 is a command line parser for C++11 and beyond that provides a
rich feature set with a simple and intuitive interface.

%prep
%autosetup -n CLI11-%{version}

%build
%cmake \
    -DCLI11_BUILD_DOCS:BOOL=FALSE \
    -DCLI11_BUILD_TESTS:BOOL=FALSE \
    -DCLI11_CXX_STANDARD=17
%cmake_build

%install
%cmake_install

%files devel
%license LICENSE
%doc README.md
%{_includedir}/CLI/
%{_datadir}/cmake/CLI11/
%{_datadir}/pkgconfig/CLI11.pc

%changelog
* Wed Dec 11 2025 DMS Team - 2.6.1-1
- Initial package for DMS COPR
