# qt6ct-kde: Qt 6 Configuration Utility with KDE theming support

Name:           qt6ct-kde
Version:        0.11
Release:        9%{?dist}
Summary:        Qt 6 Configuration Utility patched for KDE applications

License:        BSD-2-Clause
URL:            https://www.opencode.net/trialuser/qt6ct
Source0:        https://www.opencode.net/trialuser/qt6ct/-/archive/%{version}/qt6ct-%{version}.tar.gz
Patch1:         qt6ct-kde-0.11.patch

Conflicts:      qt6ct
Provides:       qt6ct = %{version}-%{release}

BuildRequires:  cmake
BuildRequires:  cmake(Qt6Core)
BuildRequires:  cmake(Qt6Gui)
BuildRequires:  cmake(Qt6Widgets)
BuildRequires:  cmake(Qt6Svg)
BuildRequires:  cmake(Qt6LinguistTools)
BuildRequires:  qt6-qttools
BuildRequires:  qt6-qtbase-private-devel
BuildRequires:  kf6-kconfig-devel
BuildRequires:  kf6-kcolorscheme-devel
BuildRequires:  kf6-kiconthemes-devel
BuildRequires:  qt6-qtdeclarative-devel
Requires:       kf6-qqc2-desktop-style

%description
qt6ct-kde is the Qt 6 Configuration Utility with patches for correct
behavior with KDE applications.
- KDE color schemes support (KColorScheme)
- Writing widget style and icon theme to kdeglobals (KStyleManager)
- KDE icon engine for correct monochrome icon colors
- QtQuick-QtWidgets style bridge (org.kde.desktop)

%prep
%autosetup -n qt6ct-%{version} -p1

%build
%cmake
%cmake_build

%install
%cmake_install

%files
%{_bindir}/qt6ct
%{_libdir}/qt6/plugins/platformthemes/libqt6ct.so
%{_libdir}/qt6/plugins/styles/libqt6ct-style.so
%{_libdir}/libqt6ct-common.so*
%{_datadir}/applications/qt6ct.desktop
%{_datadir}/qt6ct/
%license COPYING
# Port of AUR qt6ct-kde (https://aur.archlinux.org/packages/qt6ct-kde)
# KDE patch from opencode.net MR !9 (Ilya Fedin)
# KDE theming: KDE color schemes, icon engine, kdeglobals, QQC2 desktop style
# KDE theming: single patch for qt6ct 0.11 (from opencode MR !9, adjusted for 0.11)
%changelog
* Tue Feb 18 2025 avengemedia <avengemedia@users.noreply.github.com> - 0.11-8
- Initial Fedora package (port of AUR qt6ct-kde)