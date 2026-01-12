Name:           zig15
Version:        0.15.2
Release:        1%{?dist}
Summary:        Zig programming language compiler version 0.15

License:        MIT
URL:            https://ziglang.org/
Source0:        zig15-%{version}.tar.gz

BuildRequires:  tar
BuildRequires:  xz
ExclusiveArch:  x86_64 aarch64

%description
Zig is a general-purpose programming language and toolchain for maintaining
robust, optimal, and reusable software. This package provides Zig version 0.15.2,
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
cp -a zig-${ZIG_ARCH}-linux-%{version} %{buildroot}%{_libdir}/zig-0.15.2

# Create versioned symlink in /usr/bin
mkdir -p %{buildroot}%{_bindir}
ln -s %{_libdir}/zig-0.15.2/zig %{buildroot}%{_bindir}/zig-0.15

%files
%{_libdir}/zig-0.15.2/
%{_bindir}/zig-0.15

%changelog
* Fri Jan 10 2026 Avenge Media <AvengeMedia.US@gmail.com> - 0.15.2-1
- Initial zig15 package for danklinux
- Binary repackaging of official Zig 0.15.2 release
- For future Ghostty versions and other Zig projects
- Installs to /usr/lib64/zig-0.15.2 with /usr/bin/zig-0.15 symlink
