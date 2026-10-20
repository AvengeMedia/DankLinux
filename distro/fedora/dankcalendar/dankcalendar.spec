%global debug_package %{nil}

Name:               dankcalendar
Version:            2.0.0
Release:            1%{?dist}
Summary:            Calendar app for the Dux Labs desktop

License:            MIT
URL:                https://github.com/duxlabs-dev/dux-calendar
# Release tarball ships the dux-qml-common submodule and vendored Go modules
Source0:            %{url}/releases/download/v%{version}/dankcalendar-%{version}.tar.gz

BuildRequires:      golang
BuildRequires:      systemd-rpm-macros

Requires:          (quickshell-git or quickshell)
Requires:          libsecret
Requires:          qt6-qtdeclarative

Conflicts:         dankcalendar-git

%description
Dux Calendar brings Local, Google, Microsoft, CalDAV, and iCloud calendars
together in one standalone app. It runs as a lightweight daemon with a tray
icon, keeps accounts in sync, and reminds you about events.

%prep
%autosetup -n dankcalendar-%{version} -p1

%build
export GOTOOLCHAIN=auto
export GOFLAGS="-buildmode=pie -trimpath -mod=vendor -modcacherw"
export BUILD_TIME="$(date -u '+%%Y-%%m-%%d_%%H:%%M:%%S')"

# Embed the quickshell UI and build it into the binary.
rm -rf core/internal/shellembed/dist
cp -aL quickshell core/internal/shellembed/dist
rm -rf core/internal/shellembed/dist/scripts
rm -f core/internal/shellembed/dist/translations/extract_translations.py

cd core
CGO_ENABLED=0 go build \
    -tags withshell \
    -ldflags="-s -w -X main.Version=%{version} -X main.BuildTime=${BUILD_TIME}" \
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
* Tue Oct 20 2026 github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com> - 2.0.0-1
- update to 2.0.0

* Fri Oct 16 2026 Avenge Media <AvengeMedia.US@gmail.com> - 1.6.1-1
- Initial stable package
