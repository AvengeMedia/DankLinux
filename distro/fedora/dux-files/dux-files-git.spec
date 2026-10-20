%global debug_package %{nil}

%global commit      f646769cc6de61354402bba0ee8ee3bb7d52d588
%global commits     66
%global snapdate    20261020
%global tag         2.0.1
# dux-qml-common submodule commit for %%{commit} (GitHub archives ship submodules empty)
%global common_commit ebf5e6c002da1bdaa4aaa2f319fea7b8507abc42

Name:               dux-files-git
Version:            %{tag}+git%{commits}.%(c=%{commit}; echo ${c:0:8})
Release:            1%{?dist}
Summary:            File manager for the Dux Labs desktop (git)

License:            MIT
URL:                https://github.com/duxlabs-dev/dux-files
Source0:            %{url}/archive/%{commit}/dux-files-%{commit}.tar.gz
Source1:            https://github.com/duxlabs-dev/dux-qml-common/archive/%{common_commit}/dux-qml-common-%{common_commit}.tar.gz

BuildRequires:      golang
BuildRequires:      git-core
BuildRequires:      make
BuildRequires:      systemd-rpm-macros

Requires:          (quickshell-git or quickshell)
Requires:          qt6-qtdeclarative
Recommends:        polkit
Recommends:        gvfs
Recommends:        udisks2
Recommends:        bubblewrap
Recommends:        xdg-desktop-portal
Suggests:          ffmpegthumbnailer
Suggests:          poppler-utils

Conflicts:         dux-files
Provides:          dfiles = %{version}-%{release}

%description
Dux Files is a standalone file manager for Wayland. A small Go daemon does
the file work and a Quickshell UI sits on top of it, with tabs, split panes,
search, file operations with undo and archives. It also handles
org.freedesktop.FileManager1 and provides an xdg-desktop-portal file chooser.

This is the git development package built from upstream master.

%prep
%autosetup -n dux-files-%{commit} -p1
rm -rf dux-qml-common
tar -xzf %{SOURCE1}
mv dux-qml-common-%{common_commit} dux-qml-common

%build
export GOTOOLCHAIN=auto
export GOFLAGS="-buildmode=pie -trimpath -mod=readonly -modcacherw"
export VERSION="%{tag}+git%{commits}.%(c=%{commit}; echo ${c:0:8})"
export BUILD_TIME="$(date -u '+%%Y-%%m-%%d_%%H:%%M:%%S')"
export COMMIT="$(echo %{commit} | cut -c1-8)"

# Embed the quickshell UI and build it into the binary.
make -C core sync-shell

cd core
CGO_ENABLED=0 go build \
    -tags withshell \
    -ldflags="-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME} -X main.Commit=${COMMIT}" \
    -o ../dfiles ./cmd/dfiles
cd ..

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
* Tue Oct 20 2026 Avenge Media <AvengeMedia.US@gmail.com> - 0.0.1+git64.14d39823-1
- Initial git package (commit 14d39823)
