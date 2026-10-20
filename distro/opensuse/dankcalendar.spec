%global debug_package %{nil}

Name:           dankcalendar
Version:        1.6.1
Release:        1%{?dist}
Summary:        Calendar app for the Dux Labs desktop

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-calendar
Source0:        dankcalendar-%{version}.tar.gz
Source1:        https://github.com/duxlabs-dev/dux-calendar/releases/download/v%{version}/dcal-linux-amd64.gz
Source2:        https://github.com/duxlabs-dev/dux-calendar/releases/download/v%{version}/dcal-linux-arm64.gz

BuildRequires:  systemd-rpm-macros

Requires:       (quickshell-git or quickshell)
Requires:       libsecret-1-0
Requires:       libQt6Quick6

Conflicts:      dankcalendar-git

%description
Dux Calendar brings Local, Google, Microsoft, CalDAV, and iCloud calendars
together in one standalone app. It runs as a lightweight daemon with a tray
icon, keeps accounts in sync, and reminds you about events.

%prep
%setup -q -n dankcalendar-%{version}
%ifarch x86_64
gunzip -c %{SOURCE1} > dcal
%endif
%ifarch aarch64
gunzip -c %{SOURCE2} > dcal
%endif
chmod +x dcal

%build
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
* Fri Oct 16 2026 Avenge Media <AvengeMedia.US@gmail.com> - 1.6.1-1
- Initial stable package
