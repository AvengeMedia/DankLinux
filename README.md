# DankLinux Package Repository

<div align="center">
  <a href="https://danklinux.com">
    <img src="assets/danklogo.svg" alt="DankMaterialShell" width="200">
  </a>

  ### DMS Wayland desktop environment packages built for Debian, Ubuntu, and OpenSUSE

  Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

[![Documentation](https://img.shields.io/badge/docs-danklinux.com-9ccbfb?style=for-the-badge&labelColor=101418)](https://danklinux.com/docs)
[![GitHub stars](https://img.shields.io/github/stars/AvengeMedia/DankLinux?style=for-the-badge&labelColor=101418&color=ffd700)](https://github.com/AvengeMedia/DankMaterialShell/stargazers)
[![GitHub License](https://img.shields.io/github/license/AvengeMedia/DankMaterialShell?style=for-the-badge&labelColor=101418&color=b9c8da)](https://github.com/AvengeMedia/DankMaterialShell/blob/master/LICENSE)
[![Ko-Fi donate](https://img.shields.io/badge/donate-kofi?style=for-the-badge&logo=ko-fi&logoColor=ffffff&label=ko-fi&labelColor=101418&color=f16061&link=https%3A%2F%2Fko-fi.com%2Favengemediallc)](https://ko-fi.com/avengemediallc)

</div>

## Available Packages

### Core Compositor
- **niri** - Scrollable-tiling Wayland compositor with smooth animations (stable release)
- **niri-git** - Latest development version of niri with cutting-edge features

### Shell & Utilities
- **quickshell-git** - QtQuick-based Wayland desktop shell framework
- **matugen** - Material Design 3 color palette generator for themes
- **cliphist** - Wayland clipboard manager with history support

### Desktop Environment
- **dms** - DankMaterialShell complete desktop environment (stable release)
- **dms-git** - Latest development version of DMS
- **danksearch** - Application launcher and search tool
- **dgop** - DankLinux system tools and utilities

## Installation

### Debian 13 (Trixie)

#### Prerequisites
```bash
# Install curl if not already available
sudo apt install curl
```

#### Option 1: Standalone Packages (Recommended for individual components)

Install just the packages you need from danklinux:

```bash
# Add danklinux repository
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Update and install
sudo apt update

# Install niri compositor (stable)
sudo apt install niri

# Or install niri-git (latest development)
sudo apt install niri-git

# Install quickshell and utilities
sudo apt install quickshell-git matugen cliphist
```

#### Option 2: DMS Desktop Environment (Complete setup)

For a full desktop environment experience, add both danklinux and dms repositories:

**Stable Release:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Add dms repository (stable release)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/dms.list

# Update and install DMS
sudo apt update
sudo apt install dms
```

**Development Version:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Add dms-git repository (development version)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms-git/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms-git.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms-git.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms-git/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/dms-git.list

# Update and install DMS git version
sudo apt update
sudo apt install dms-git
```

### Debian Testing (Rolling)

For users who want to stay on the latest Debian testing branch:

#### Prerequisites
```bash
# Install curl if not already available
sudo apt install curl
```

#### Option 1: Standalone Packages (Recommended for individual components)

Install just the packages you need from danklinux:

```bash
# Add danklinux repository
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Update and install
sudo apt update

# Install niri compositor (stable)
sudo apt install niri

# Or install niri-git (latest development)
sudo apt install niri-git

# Install quickshell and utilities
sudo apt install quickshell-git matugen cliphist
```

#### Option 2: DMS Desktop Environment (Complete setup)

For a full desktop environment experience, add both danklinux and dms repositories:

**Stable Release:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Add dms repository (stable release)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/dms.list

# Update and install DMS
sudo apt update
sudo apt install dms
```

**Development Version:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list

# Add dms-git repository (development version)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms-git/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms-git.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms-git.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms-git/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/dms-git.list

# Update and install DMS git version
sudo apt update
sudo apt install dms-git
```

### Ubuntu (25.10 Questing and newer)

Ubuntu packages are available via Launchpad PPAs:

#### Option 1: Standalone Packages (Recommended for individual components)

Install just the packages you need from danklinux PPA:

```bash
# Add danklinux PPA
sudo add-apt-repository ppa:avengemedia/danklinux
sudo apt update

# Install niri compositor (stable)
sudo apt install niri

# Or install niri-git (latest development)
sudo apt install niri-git

# Install quickshell and utilities
sudo apt install quickshell-git matugen cliphist
```

#### Option 2: DMS Desktop Environment (Complete setup)

For a full desktop environment experience, add both danklinux and dms PPAs:

**Stable Release:**
```bash
# Add danklinux PPA (provides niri, quickshell, etc.)
sudo add-apt-repository ppa:avengemedia/danklinux

# Add dms PPA (stable release)
sudo add-apt-repository ppa:avengemedia/dms

# Update and install DMS
sudo apt update
sudo apt install dms
```

**Development Version:**
```bash
# Add danklinux PPA (provides niri, quickshell, etc.)
sudo add-apt-repository ppa:avengemedia/danklinux

# Add dms-git PPA (development version)
sudo add-apt-repository ppa:avengemedia/dms-git

# Update and install DMS git version
sudo apt update
sudo apt install dms-git
```

### OpenSUSE Tumbleweed

#### Option 1: Standalone Packages (Recommended for individual components)

Install just the packages you need from danklinux:

```bash
# Add danklinux repository
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/openSUSE_Tumbleweed/home:AvengeMedia:danklinux.repo
sudo zypper refresh

# Install niri compositor (stable)
sudo zypper install niri

# Or install niri-git (latest development)
sudo zypper install niri-git

# Install quickshell and utilities
sudo zypper install quickshell-git matugen cliphist
```

#### Option 2: DMS Desktop Environment (Complete setup)

For a full desktop environment experience, add both danklinux and dms repositories:

**Stable Release:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/openSUSE_Tumbleweed/home:AvengeMedia:danklinux.repo

# Add dms repository (stable release)
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo

# Refresh and install DMS
sudo zypper refresh
sudo zypper install dms
```

**Development Version:**
```bash
# Add danklinux repository (provides niri, quickshell, etc.)
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/openSUSE_Tumbleweed/home:AvengeMedia:danklinux.repo

# Add dms-git repository (development version)
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:dms-git/openSUSE_Tumbleweed/home:AvengeMedia:dms-git.repo

# Refresh and install DMS git version
sudo zypper refresh
sudo zypper install dms-git
```

### Architecture Support
All packages are available for:
- **x86_64** (AMD64) - Fully supported and tested
- **aarch64** (ARM64) - Available for compatible devices

## DMS Desktop Environment

DankMaterialShell (DMS) provides a complete desktop environment built on:
- **Niri** - Scrollable tiling Wayland compositor
- **Quickshell** - Modern shell UI framework
- **Material Design 3** - Consistent theming with matugen

### Repository Variants

**Stable Repository** (`home:AvengeMedia:dms`)
- Tagged releases only
- Recommended for production use
- Less frequent updates

**Git Repository** (`home:AvengeMedia:dms-git`)
- Latest commits from master branch
- Cutting-edge features
- Daily/weekly updates
- May have occasional bugs

## Upstream Projects

- [Niri](https://github.com/YaLTeR/niri) - Scrollable-tiling Wayland compositor
- [Quickshell](https://github.com/outfoxxed/quickshell) - QtQuick desktop shell toolkit
- [Matugen](https://github.com/InioX/matugen) - Material You color generation tool
- [Cliphist](https://github.com/sentriz/cliphist) - Wayland clipboard manager
- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) - Complete desktop environment

## Getting Started

After installation, you can:

1. **Select niri** from your display manager's session menu
2. **Configure niri** by editing `~/.config/niri/config.kdl`
3. **Start DMS shell** automatically with niri session

For detailed configuration and usage, see the [DankMaterialShell documentation](https://github.com/AvengeMedia/DankMaterialShell).

## Troubleshooting

### Verify Installation
```bash
# Check installed packages (Debian)
dpkg -l | grep -E "(dms|niri|quickshell|matugen|cliphist)"

# Check installed packages (OpenSUSE)
rpm -qa | grep -E "(dms|niri|quickshell|matugen|cliphist)"

# Verify versions
niri --version
quickshell --version
```

### Repository Issues
If you encounter repository errors:

**Debian:**
```bash
sudo apt update --fix-missing
sudo apt-key adv --refresh-keys
```

**OpenSUSE:**
```bash
sudo zypper refresh
sudo zypper clean
```

## Build Status

Monitor package builds at:
- [danklinux builds](https://build.opensuse.org/project/show/home:AvengeMedia:danklinux)
- [dms builds](https://build.opensuse.org/project/show/home:AvengeMedia:dms)
- [dms-git builds](https://build.opensuse.org/project/show/home:AvengeMedia:dms-git)

## Contributing

Package specifications and build scripts are maintained in this repository. To report issues or contribute:
1. Check existing issues at the [issue tracker](https://github.com/AvengeMedia/DankMaterialShell/issues)
2. For packaging bugs, include distribution and architecture details
3. For upstream bugs, report to the respective project repositories

## License

Individual packages are licensed under their respective upstream licenses:
- **Niri**: GPL-3.0
- **Quickshell**: LGPL-3.0
- **Matugen**: GPL-2.0
- **Cliphist**: GPL-3.0
- **DMS**: GPL-3.0
