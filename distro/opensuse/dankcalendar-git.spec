%global debug_package %{nil}

Name:           dankcalendar-git
Version:        0.1.2+git14.677116ed
Release:        1%{?dist}
Summary:        Calendar app for the Dank Linux desktop (git)

License:        MIT
URL:            https://github.com/AvengeMedia/dankcalendar
Source0:        dankcalendar.tar.gz

BuildRequires:  golang >= 1.25
BuildRequires:  systemd-rpm-macros

Requires:       (quickshell-git or quickshell)
Requires:       libsecret-1-0
Requires:       libQt6Quick6

%description
DankCalendar brings Local, Google, Microsoft, CalDAV, and iCloud calendars
together in one standalone app. It runs as a lightweight daemon with a tray
icon, keeps accounts in sync, and reminds you about events.

This is the git development package built from upstream master.

%prep
%setup -q -n dankcalendar

%build
# OBS has no network; distro Go may be older than go.mod requires (e.g. 16.1, Debian 13).
# Use the Go toolchain bundled into the source tarball at OBS prep time.
case "$(uname -m)" in
    x86_64) GO_HOST_ARCH=amd64 ;;
    aarch64) GO_HOST_ARCH=arm64 ;;
    *) echo "unsupported architecture: $(uname -m)"; exit 1 ;;
esac
export PATH="$(pwd)/.go-toolchain/${GO_HOST_ARCH}/go/bin:${PATH}"
export GOTOOLCHAIN=local
export GOFLAGS="-buildmode=pie -trimpath -mod=vendor -modcacherw"
export VERSION="%{version}"
export BUILD_TIME="$(date -u '+%%Y-%%m-%%d_%%H:%%M:%%S')"
export COMMIT="$(echo %{version} | sed -n 's/.*\.\([a-f0-9]\{8\}\)$/\1/p')"

cd core
CGO_ENABLED=0 go build \
    -ldflags="-s -w -X main.Version=${VERSION} -X main.BuildTime=${BUILD_TIME} -X main.Commit=${COMMIT}" \
    -o ../dcal ./cmd/dcal
cd ..

mkdir -p completions
./dcal completion bash > completions/dcal
./dcal completion zsh > completions/_dcal
./dcal completion fish > completions/dcal.fish

%install
install -Dm755 dcal %{buildroot}%{_bindir}/dcal

install -d %{buildroot}%{_datadir}/quickshell/dankcal
cp -a quickshell/. %{buildroot}%{_datadir}/quickshell/dankcal/

install -Dm644 assets/dankcalendar.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dankcalendar.svg

install -Dm644 assets/com.danklinux.dankcalendar.desktop \
    %{buildroot}%{_datadir}/applications/com.danklinux.dankcalendar.desktop

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
%{_datadir}/applications/com.danklinux.dankcalendar.desktop
%dir %{_datadir}/icons/hicolor
%dir %{_datadir}/icons/hicolor/scalable
%dir %{_datadir}/icons/hicolor/scalable/apps
%{_datadir}/icons/hicolor/scalable/apps/dankcalendar.svg
%dir %{_datadir}/quickshell
%dir %{_datadir}/quickshell/dankcal
%{_datadir}/quickshell/dankcal/
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
* Mon Jun 15 2025 Avenge Media <AvengeMedia.US@gmail.com> - 0.1.2+git14.677116ed-1
- Initial git package (commit 677116ed)
