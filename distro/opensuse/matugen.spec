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
# x86_64: use pre-built binary from Source0
%setup -q -c -T -n matugen-%{version}
tar -xzf %{SOURCE0}
%endif
%ifarch aarch64
# aarch64: build from source with vendored deps (Source1)
# Source1 extracts to matugen-source/
%setup -q -T -b 1 -n matugen-source
%endif

%build
%ifarch x86_64
# Pre-built binary, nothing to build
true
%endif
%ifarch aarch64
# Build from source with vendored deps
# Fix vendor checksums for offline build
for checksum in vendor/*/.cargo-checksum.json; do
    if [ -f "$checksum" ]; then
        pkg=$(cat "$checksum" | grep -o '"package":"[^"]*"' | cut -d'"' -f4)
        echo "{\"files\":{},\"package\":\"$pkg\"}" > "$checksum"
    fi
done
cargo build --offline --release
%endif

%install
%ifarch x86_64
# Install pre-built binary
if [ -f matugen ]; then
    install -Dm755 matugen %{buildroot}%{_bindir}/matugen
elif [ -f matugen-*/matugen ]; then
    install -Dm755 matugen-*/matugen %{buildroot}%{_bindir}/matugen
else
    echo "Error: Cannot find matugen binary"
    exit 1
fi
%endif
%ifarch aarch64
# Install built binary
install -Dm755 target/release/matugen %{buildroot}%{_bindir}/matugen
%endif

%files
%{_bindir}/matugen

%changelog
* Tue Nov 25 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.0.0-2
- Enable aarch64 builds with vendored Rust dependencies
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com> - 3.0.0-1
- Initial OBS package
