%global debug_package %{nil}

Name:           dux-files
Version:        2.0.0
Release:        1%{?dist}
Summary:        File manager for the Dux Labs desktop

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-files
Source0:        dux-files-%{version}.tar.gz
Source1:        https://github.com/duxlabs-dev/dux-files/releases/download/v%{version}/dfiles-linux-amd64.gz
Source2:        https://github.com/duxlabs-dev/dux-files/releases/download/v%{version}/dfiles-linux-arm64.gz

BuildRequires:  systemd-rpm-macros

Requires:       (quickshell-git or quickshell)
Requires:       libQt6Quick6
Recommends:     polkit
Recommends:     gvfs
Recommends:     udisks2
Recommends:     bubblewrap
Recommends:     xdg-desktop-portal
Recommends:     qt6-pdf-imports
Suggests:       ffmpegthumbnailer
Suggests:       poppler-tools

Conflicts:      dux-files-git
Provides:       dfiles = %{version}-%{release}

%description
Dux Files is a standalone file manager for Wayland. A small Go daemon does
the file work and a Quickshell UI sits on top of it, with tabs, split panes,
search, file operations with undo and archives. It also handles
org.freedesktop.FileManager1 and provides an xdg-desktop-portal file chooser.

%prep
%setup -q -n dux-files-%{version}
%ifarch x86_64
gunzip -c %{SOURCE1} > dfiles
%endif
%ifarch aarch64
gunzip -c %{SOURCE2} > dfiles
%endif
chmod +x dfiles

%build
mkdir -p completions
./dfiles completion bash > completions/dfiles
./dfiles completion zsh > completions/_dfiles
./dfiles completion fish > completions/dfiles.fish

%install
install -Dm755 dfiles %{buildroot}%{_bindir}/dfiles

install -Dm644 assets/dev.duxlabs.files.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.files.svg

install -Dm644 assets/dev.duxlabs.files.desktop \
    %{buildroot}%{_datadir}/applications/dev.duxlabs.files.desktop

install -Dm644 assets/dev.duxlabs.files.metainfo.xml \
    %{buildroot}%{_datadir}/metainfo/dev.duxlabs.files.metainfo.xml

install -Dm644 assets/dev.duxlabs.files.policy \
    %{buildroot}%{_datadir}/polkit-1/actions/dev.duxlabs.files.policy

install -Dm644 assets/dbus/dev.duxlabs.files.FileManager1.service \
    %{buildroot}%{_datadir}/dbus-1/services/dev.duxlabs.files.FileManager1.service
install -Dm644 assets/dbus/org.freedesktop.impl.portal.desktop.dfiles.service \
    %{buildroot}%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.dfiles.service

install -Dm644 assets/portal/dfiles.portal \
    %{buildroot}%{_datadir}/xdg-desktop-portal/portals/dfiles.portal

install -Dm644 assets/systemd/dfiles.service \
    %{buildroot}%{_userunitdir}/dfiles.service

install -Dm644 completions/dfiles \
    %{buildroot}%{_datadir}/bash-completion/completions/dfiles
install -Dm644 completions/_dfiles \
    %{buildroot}%{_datadir}/zsh/site-functions/_dfiles
install -Dm644 completions/dfiles.fish \
    %{buildroot}%{_datadir}/fish/vendor_completions.d/dfiles.fish

%files
%license LICENSE
%{_bindir}/dfiles
%{_userunitdir}/dfiles.service
%{_datadir}/applications/dev.duxlabs.files.desktop
%{_datadir}/metainfo/dev.duxlabs.files.metainfo.xml
%dir %{_datadir}/polkit-1
%dir %{_datadir}/polkit-1/actions
%{_datadir}/polkit-1/actions/dev.duxlabs.files.policy
%dir %{_datadir}/dbus-1
%dir %{_datadir}/dbus-1/services
%{_datadir}/dbus-1/services/dev.duxlabs.files.FileManager1.service
%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.dfiles.service
%dir %{_datadir}/xdg-desktop-portal
%dir %{_datadir}/xdg-desktop-portal/portals
%{_datadir}/xdg-desktop-portal/portals/dfiles.portal
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.files.svg
%dir %{_datadir}/bash-completion
%dir %{_datadir}/bash-completion/completions
%{_datadir}/bash-completion/completions/dfiles
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_dfiles
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/dfiles.fish

%changelog
* Tue Oct 20 2026 Avenge Media <AvengeMedia.US@gmail.com> - 2.0.0-1
- Initial stable package
