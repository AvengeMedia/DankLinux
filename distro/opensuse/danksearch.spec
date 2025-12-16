Name:           danksearch
Version:        0.1.1
Release:        1%{?dist}
Summary:        Fast file search utility for DMS

License:        MIT
URL:            https://github.com/AvengeMedia/danksearch
Source0:        https://github.com/AvengeMedia/danksearch/releases/download/v%{version}/dsearch-linux-amd64.gz
Source1:        https://github.com/AvengeMedia/danksearch/releases/download/v%{version}/dsearch-linux-arm64.gz

%description
DankSearch is a fast file search utility designed for DankMaterialShell.
It provides efficient file and content search capabilities with minimal
dependencies.

%prep
%ifarch x86_64
gunzip -c %{SOURCE0} > danksearch
%endif
%ifarch aarch64
gunzip -c %{SOURCE1} > danksearch
%endif
chmod +x danksearch

%build

%install
install -Dm755 danksearch %{buildroot}%{_bindir}/danksearch
ln -s danksearch %{buildroot}%{_bindir}/dsearch

%files
%{_bindir}/danksearch
%{_bindir}/dsearch

%changelog
* Sat Dec 13 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.1.0-1
- Update to upstream version 0.1.0
* Fri Nov 22 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.0.7-1
- Add dsearch symlink for compatibility
