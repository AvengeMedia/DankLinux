Name:           cliphist
Version:        0.7.0
Release:        1%{?dist}
Summary:        Wayland clipboard manager with text and image support

License:        GPL-3.0
URL:            https://github.com/sentriz/cliphist
Source0:        cliphist.tar.gz

BuildRequires:  golang >= 1.16
BuildRequires:  tar
Requires:       wl-clipboard
Requires:       xdg-utils

%description
cliphist is a clipboard manager for Wayland that stores both text and
image data. It integrates with wl-clipboard to provide clipboard history
that persists across sessions.

%prep
%setup -q -n cliphist-0.7.0

%build
go build -mod=vendor -ldflags="-s -w" -o cliphist

%install
install -Dm755 cliphist %{buildroot}%{_bindir}/cliphist

%files
%license LICENSE
%{_bindir}/cliphist

%changelog
* Wed Nov 20 2025 Avenge Media <AvengeMedia.US@gmail.com>
- Initial OBS package
