Name:           dgop
Version:        0.1.12
Release:        1%{?dist}
Summary:        Stateless CPU/GPU monitor for DankMaterialShell

License:        MIT
URL:            https://github.com/AvengeMedia/dgop
Source0:        https://github.com/AvengeMedia/dgop/releases/download/v%{version}/dgop-linux-amd64.gz
Source1:        https://github.com/AvengeMedia/dgop/releases/download/v%{version}/dgop-linux-arm64.gz

%description
DGOP is a stateless system monitoring tool that provides CPU, GPU, memory, and 
network statistics. Designed for integration with DankMaterialShell but can be 
used standalone.

%prep
%ifarch x86_64
gunzip -c %{SOURCE0} > dgop
%endif
%ifarch aarch64
gunzip -c %{SOURCE1} > dgop
%endif
chmod +x dgop

%build

%install
install -Dm755 dgop %{buildroot}%{_bindir}/dgop

%files
%{_bindir}/dgop

%changelog
* Tue Nov 18 2025 AvengeMedia <maintainer@avengemedia.com> - 0.1.11-1
- Initial OpenSUSE package
