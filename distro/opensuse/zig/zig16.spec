Name:           zig16
Version:        0.16.0
Release:        1%{?dist}
Summary:        Zig programming language compiler version 0.16

License:        MIT
URL:            https://ziglang.org/
Source0:        zig16-%{version}.tar.gz

BuildRequires:  tar
BuildRequires:  xz
ExclusiveArch:  x86_64 aarch64

%description
Zig is a general-purpose programming language and toolchain for maintaining
robust, optimal, and reusable software. This package provides Zig version 0.16.0,
which can coexist with other Zig versions on the same system.

%prep
%setup -q -c
%ifarch x86_64
tar -xJf zig-x86_64-linux-%{version}.tar.xz
%endif
%ifarch aarch64
tar -xJf zig-aarch64-linux-%{version}.tar.xz
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
cp -a zig-${ZIG_ARCH}-linux-%{version} %{buildroot}%{_libdir}/zig-0.16.0

# Create versioned symlink in /usr/bin
mkdir -p %{buildroot}%{_bindir}
ln -s %{_libdir}/zig-0.16.0/zig %{buildroot}%{_bindir}/zig-0.16

%files
%{_libdir}/zig-0.16.0/
%{_bindir}/zig-0.16

%changelog
* Wed Sep 09 2026 Avenge Media <AvengeMedia.US@gmail.com> - 0.16.0-1
- Initial zig16 package for danklinux
- Binary repackaging of official Zig 0.16.0 release
- Required for upcoming Ghostty 1.3.2 (minimum_zig_version = 0.16.0)
- Installs to /usr/lib64/zig-0.16.0 with /usr/bin/zig-0.16 symlink
