Name:           matugen
Version:        3.0.0
Release:        1%{?dist}
Summary:        Material You color generation tool

License:        GPL-2.0-or-later
URL:            https://github.com/InioX/matugen
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz#/matugen-%{version}.tar.gz

BuildRequires:  rust
BuildRequires:  cargo

%description
Material You color generation tool for theming.

%prep
%autosetup -n matugen-%{version}

%build
cargo build --release

%install
install -Dm755 target/release/matugen %{buildroot}%{_bindir}/matugen

%files
%{_bindir}/matugen
%license LICENSE
%doc README.md

%changelog
* Mon Oct 07 2024 Purian23 <purian23@users.noreply.github.com> - 2.4.1-1
- Initial Copr package release
- Version 2.4.1
