%global debug_package %{nil}

Name:           dgop
Version:        0.1.12
Epoch:          1
Release:        1%{?dist}
Summary:        System monitoring CLI and REST API

License:        MIT
URL:            https://github.com/AvengeMedia/dgop

# Pre-built binaries from GitHub releases - using /latest/download/ for automatic updates
Source0:        %{url}/releases/latest/download/dgop-linux-amd64.gz
Source1:        %{url}/releases/latest/download/dgop-linux-amd64.gz.sha256
Source2:        %{url}/releases/latest/download/dgop-linux-arm64.gz
Source3:        %{url}/releases/latest/download/dgop-linux-arm64.gz.sha256

BuildRequires:  gzip
BuildRequires:  coreutils

Requires:       glibc

%description
dgop is a Go-based system monitoring tool that provides both a CLI interface
and REST API for retrieving system metrics including CPU, memory, disk, network,
processes, and GPU information.

Features:
- Interactive TUI with real-time system monitoring
- REST API server with OpenAPI specification
- JSON output for all metrics
- GPU temperature monitoring (NVIDIA)
- Lightweight single-binary deployment

%prep
# Extract pre-built binary for the appropriate architecture
%ifarch x86_64
# Verify checksum of compressed file
echo "$(cat %{SOURCE1} | cut -d' ' -f1)  %{SOURCE0}" | sha256sum -c - || { echo "Checksum mismatch!"; exit 1; }
gunzip -c %{SOURCE0} > dgop
%endif

%ifarch aarch64
# Verify checksum of compressed file
echo "$(cat %{SOURCE3} | cut -d' ' -f1)  %{SOURCE2}" | sha256sum -c - || { echo "Checksum mismatch!"; exit 1; }
gunzip -c %{SOURCE2} > dgop
%endif

chmod +x dgop

%build
# Using pre-built binary - nothing to build

%install
install -Dm755 dgop %{buildroot}%{_bindir}/dgop

%files
%{_bindir}/dgop

%changelog
* Wed Dec 11 2025 Purian23 <purian23@users.noreply.github.com> - 1:0.1.11-1
- Add Epoch: 1 to supersede old bundled dgop 0.6.2 from dms package
- Updated to version 0.1.11
- Standalone dgop package now properly replaces legacy bundled version
