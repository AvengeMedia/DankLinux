%global debug_package %{nil}

%global commit      d8825c6f66d9218920d97e9fde9cc02acd0b5584
%global commits     248
%global snapdate    20261020
%global tag         1.6.2
# dux-qml-common submodule commit for %%{commit} (GitHub archives ship submodules empty)
%global common_commit ebf5e6c002da1bdaa4aaa2f319fea7b8507abc42

Name:               dankcalendar-git
Version:            %{tag}+git%{commits}.%(c=%{commit}; echo ${c:0:8})
Release:            2%{?dist}
Summary:            Calendar app for the Dux Labs desktop (git)

License:            MIT
URL:                https://github.com/duxlabs-dev/dux-calendar
Source0:            %{url}/archive/%{commit}/dankcalendar-%{commit}.tar.gz
Source1:            https://github.com/duxlabs-dev/dux-qml-common/archive/%{common_commit}/dux-qml-common-%{common_commit}.tar.gz

BuildRequires:      golang >= 1.25
BuildRequires:      git-core
BuildRequires:      systemd-rpm-macros

Requires:          (quickshell-git or quickshell)
Requires:          libsecret
Requires:          qt6-qtdeclarative

%description
Dux Calendar brings Local, Google, Microsoft, CalDAV, and iCloud calendars
together in one standalone app. It runs as a lightweight daemon with a tray
icon, keeps accounts in sync, and reminds you about events.

This is the git development package built from upstream master.

%prep
%autosetup -n dux-calendar-%{commit} -p1
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
rm -rf core/internal/shellembed/dist
cp -aL quickshell core/internal/shellembed/dist
rm -rf core/internal/shellembed/dist/scripts
rm -f core/internal/shellembed/dist/translations/extract_translations.py

cd core
CGO_ENABLED=0 go build \
    -tags withshell \
    -ldflags="-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME} -X main.Commit=${COMMIT}" \
    -o ../dcal ./cmd/dcal
cd ..

mkdir -p completions
./dcal completion bash > completions/dcal
./dcal completion zsh > completions/_dcal
./dcal completion fish > completions/dcal.fish

%install
install -Dm755 dcal %{buildroot}%{_bindir}/dcal

install -Dm644 assets/dev.duxlabs.calendar.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.calendar.svg

install -Dm644 assets/dev.duxlabs.calendar.desktop \
    %{buildroot}%{_datadir}/applications/dev.duxlabs.calendar.desktop

install -Dm644 assets/systemd/dcal.service \
    %{buildroot}%{_userunitdir}/dcal.service

install -Dm644 completions/dcal \
    %{buildroot}%{_datadir}/bash-completion/completions/dcal
install -Dm644 completions/_dcal \
    %{buildroot}%{_datadir}/zsh/site-functions/_dcal
install -Dm644 completions/dcal.fish \
    %{buildroot}%{_datadir}/fish/vendor_completions.d/dcal.fish

%files
%license LICENSE
%{_bindir}/dcal
%{_userunitdir}/dcal.service
%{_datadir}/applications/dev.duxlabs.calendar.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/scalable/apps/dev.duxlabs.calendar.svg
%dir %{_datadir}/bash-completion
%dir %{_datadir}/bash-completion/completions
%{_datadir}/bash-completion/completions/dcal
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_dcal
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/dcal.fish

%changelog
* Mon Jul 13 2026 Avenge Media <AvengeMedia.US@gmail.com> - 0.2.4+git86.5be85575-2
- Build with -tags withshell; stop installing QML (UI embedded in binary)
* Mon Jun 15 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.1.2+git14.677116ed-1
- Initial git package (commit 677116ed)
