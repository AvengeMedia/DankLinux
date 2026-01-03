Name:           matugen
Version:        3.1.0
Release:        1%{?dist}
Summary:        Material You color generation tool

License:        GPL-2.0
URL:            https://github.com/InioX/matugen
Source0:        matugen-%{version}.tar.gz

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  pkgconfig(x11)
Requires:       libX11-6

%description
matugen is a Material You color palette generator that generates color
schemes from images and applies them to various applications and desktop
environments.

%prep
# Build from source with vendored deps
# Source0 extracts to matugen-%{version}/
%setup -q -T -b 0 -n matugen-%{version}

%build
# Fix vendor checksums for offline build
for checksum in vendor/*/.cargo-checksum.json; do
    if [ -f "$checksum" ]; then
        pkg=$(cat "$checksum" | grep -o '"package":"[^"]*"' | cut -d'"' -f4)
        echo "{\"files\":{},\"package\":\"$pkg\"}" > "$checksum"
    fi
done
cargo build --offline --release

%install
install -Dm755 target/release/matugen %{buildroot}%{_bindir}/matugen

%files
%{_bindir}/matugen

%changelog
* Thu Nov 27 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.1.0-1
- Update to upstream version 3.1.0
* Tue Nov 25 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.0.0-2
- Enable aarch64 builds with vendored Rust dependencies
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.0.0-1
- Initial OBS package
