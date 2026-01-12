Name:           zig14
Version:        0.14.0
Release:        1%{?dist}
Summary:        Zig programming language compiler version 0.14

License:        MIT
URL:            https://ziglang.org/
Source0:        zig14-%{version}.tar.gz

BuildRequires:  tar
BuildRequires:  xz
ExclusiveArch:  x86_64 aarch64

%description
Zig is a general-purpose programming language and toolchain for maintaining
robust, optimal, and reusable software. This package provides Zig version 0.14.0,
which can coexist with other Zig versions on the same system.

%prep
%setup -q -c
%ifarch x86_64
tar -xJf zig-linux-x86_64-%{version}.tar.xz
%endif
%ifarch aarch64
tar -xJf zig-linux-aarch64-%{version}.tar.xz
%endif

%build
# Using official binaries

%install

%ifarch x86_64
ZIG_ARCH=x86_64
%endif
%ifarch aarch64
ZIG_ARCH=aarch64
%endif

# Install to versioned directory
mkdir -p %{buildroot}%{_libdir}
cp -a zig-linux-${ZIG_ARCH}-%{version} %{buildroot}%{_libdir}/zig-0.14.0

# Create versioned symlink in /usr/bin
mkdir -p %{buildroot}%{_bindir}
ln -s %{_libdir}/zig-0.14.0/zig %{buildroot}%{_bindir}/zig-0.14

%files
%{_libdir}/zig-0.14.0/
%{_bindir}/zig-0.14

%changelog
* Fri Jan 10 2026 Avenge Media <AvengeMedia.US@gmail.com> - 0.14.0-1
- Initial zig14 package for danklinux
- Binary repackaging of official Zig 0.14.0 release
- Required for Ghostty 1.2.3 builds
- Installs to /usr/lib64/zig-0.14.0 with /usr/bin/zig-0.14 symlink
