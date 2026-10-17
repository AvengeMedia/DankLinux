Name:           cava
Version:        1.0.0
Release:        1%{?dist}
Summary:        Console-based Audio Visualizer for Alsa

License:        MIT
URL:            https://github.com/karlstav/cava
Source0:        %{url}/archive/%{version}/%{name}-%{version}.tar.gz

BuildRequires:  alsa-lib-devel
BuildRequires:  fftw-devel
BuildRequires:  pulseaudio-libs-devel
BuildRequires:  libtool
BuildRequires:  ncurses-devel
BuildRequires:  iniparser-devel
BuildRequires:  make
BuildRequires:  gcc
BuildRequires:  autoconf
BuildRequires:  automake
BuildRequires:  pkgconfig

%description
C.A.V.A. is a bar spectrum analyzer for audio using ALSA for input.

%prep
%autosetup -p1
./autogen.sh

%build
%configure FONT_DIR=/lib/kbd/consolefonts LIBS=-lrt
make %{?_smp_mflags} \
    cava_LDFLAGS=

%install
%make_install
rm -f %{buildroot}%{_libdir}/libiniparser.{a,la,so}

%files
%license LICENSE
%doc README.md
%doc example_files
%{_bindir}/cava
/lib/kbd/consolefonts/cava.psf

%changelog
* Fri Oct 16 2026 Purian23 <purian23@users.noreply.github.com> - 1.0.0-1
- Initial Copr package release for EL10
- Version 1.0.0
