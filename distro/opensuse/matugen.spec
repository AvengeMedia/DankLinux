Name:           matugen
Version:        3.0.0
Release:        1%{?dist}
Summary:        Material You color generation tool

License:        GPL-2.0
URL:            https://github.com/InioX/matugen
Source0:        matugen-amd64.tar.gz
Source1:        matugen-source.tar.gz

%ifarch x86_64
Requires:       libX11-6
%else
BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  pkgconfig(x11)
Requires:       libX11-6
%endif

%description
matugen is a Material You color palette generator that generates color
schemes from images and applies them to various applications and desktop
environments.

%prep
%ifarch x86_64
%setup -q -c -T
tar -xzf %{SOURCE0}
%else
%setup -q -n matugen-%{version}
%endif

%build
%ifarch x86_64
true
%else
cargo build --release
%endif

%install
%ifarch x86_64
if [ -f matugen ]; then
    install -Dm755 matugen %{buildroot}%{_bindir}/matugen
elif [ -f matugen-*/matugen ]; then
    install -Dm755 matugen-*/matugen %{buildroot}%{_bindir}/matugen
else
    echo "Error: Cannot find matugen binary"
    exit 1
fi
%else
install -Dm755 target/release/matugen %{buildroot}%{_bindir}/matugen
%endif

%files
%{_bindir}/matugen

%changelog
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.0.0-1
- Initial OBS package
