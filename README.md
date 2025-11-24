# DankLinux Package Repository

<div align="center">
  <a href="https://danklinux.com">
    <img src="assets/danklogo.svg" alt="DankLinux" width="200">
  </a>

  ### DMS Wayland desktop environment packages built for Debian, Ubuntu, and OpenSUSE

  Built with [Quickshell](https://quickshell.org/) and [Go](https://go.dev/)

[![GitHub stars](https://img.shields.io/github/stars/AvengeMedia/danklinux?style=for-the-badge&labelColor=101418&color=ffd700)](https://github.com/AvengeMedia/danklinux/stargazers)
[![GitHub License](https://img.shields.io/github/license/AvengeMedia/danklinux?style=for-the-badge&labelColor=101418&color=b9c8da)](https://github.com/AvengeMedia/danklinux/blob/master/LICENSE)
[![OBS Build](https://img.shields.io/badge/OBS-building-success?style=for-the-badge&labelColor=101418&color=73ba25&logo=opensuse)](https://build.opensuse.org/project/show/home:AvengeMedia:danklinux)
[![Ko-Fi donate](https://img.shields.io/badge/donate-kofi?style=for-the-badge&logo=ko-fi&logoColor=ffffff&label=ko-fi&labelColor=101418&color=f16061)](https://ko-fi.com/avengemediallc)

</div>

## Available Packages

### Desktop Environment
- **dms** - DankMaterialShell desktop environment (stable release)
- **dms-git** - Latest development version of DMS with cutting-edge features

### Core Compositor
- **niri** - Scrollable-tiling Wayland compositor with smooth animations (stable release)
- **niri-git** - Latest development version of niri with cutting-edge features

### Shell & Utilities
- **quickshell-git** - QtQuick-based Wayland desktop shell framework
- **matugen** - Material Design 3 color palette generator for themes
- **cliphist** - Wayland clipboard manager with history support
- **danksearch** - Fast application launcher and file search tool
- **dgop** - System package manager integration tool

## Installation

### DMS Desktop Environment

DMS packages are available in separate OBS repositories.

> **Required**: DMS depends on packages from the danklinux repository (`quickshell-git`, `matugen`, `cliphist`, `danksearch`, `dgop`). Install the [dependencies](#dependencies-danklinux-repository) first, then install DMS. Niri is optional but recommended as the default compositor.

<details>
<summary><b>Debian 13 / Testing</b></summary>

```bash
# 1. First add danklinux repository for dependencies (see below)

# 2. Add DMS stable repository
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/dms.list
sudo apt update && sudo apt install dms

# Or for nightly builds (dms-git)
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:dms-git/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/dms-git.gpg
echo "deb [signed-by=/etc/apt/keyrings/dms-git.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/dms-git/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/dms-git.list
sudo apt update && sudo apt install dms-git
```

</details>

<details>
<summary><b>OpenSUSE Tumbleweed</b></summary>

```bash
# 1. First add danklinux repository for dependencies (see below)

# 2. Add DMS stable repository
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:dms/openSUSE_Tumbleweed/home:AvengeMedia:dms.repo
sudo zypper refresh && sudo zypper install dms

# Or for nightly builds (dms-git)
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:dms-git/openSUSE_Tumbleweed/home:AvengeMedia:dms-git.repo
sudo zypper refresh && sudo zypper install dms-git
```

</details>

> See [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) for full documentation and configuration.

---

### Dependencies (danklinux repository)

These packages are **required** for full DMS functionality:

### Debian 13 (Trixie) / Testing

```bash
# Add Debian 13 Trixie Repository 
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_13/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_13/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list
sudo apt update

# Install packages
sudo apt install niri quickshell-git matugen cliphist danksearch dgop
```

<details>
<summary><b>Alternative: Debian Testing (Rolling)</b></summary>

```bash
# Add Debian Testing Repository 
curl -fsSL https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/Debian_Testing/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/danklinux.gpg
echo "deb [signed-by=/etc/apt/keyrings/danklinux.gpg] https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/Debian_Testing/ /" | \
  sudo tee /etc/apt/sources.list.d/danklinux.list
sudo apt update && sudo apt install niri quickshell-git matugen cliphist danksearch dgop
```

</details>

---

### Ubuntu 25.10+ (Questing and newer)

> **Note**: Ubuntu 25.04 and older are not supported (require Qt 6.6+)

```bash
# Add PPA and install packages
sudo add-apt-repository ppa:avengemedia/danklinux
sudo apt update
sudo apt install niri quickshell-git matugen cliphist
```

### OpenSUSE Tumbleweed

```bash
# Add repository and install packages
sudo zypper addrepo https://download.opensuse.org/repositories/home:AvengeMedia:danklinux/openSUSE_Tumbleweed/home:AvengeMedia:danklinux.repo
sudo zypper refresh
sudo zypper install niri quickshell-git matugen cliphist danksearch dgop
```

---

## Architecture Support

All packages support:
- **x86_64 (AMD64)** - Fully tested
- **aarch64 (ARM64)** - Built for ARM devices

## Package Variants

- **Stable packages** (`dms`, `niri`, `matugen`, `cliphist`) - Tagged releases
- **Git packages** (`dms-git`, `niri-git`, `quickshell-git`) - Latest development code, updated daily

## Getting Started

1. Select **niri** or **niri-git** from your display manager
2. Configure: `~/.config/niri/config.kdl`
3. For DMS desktop environment, see [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)

## Upstream Projects

- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) - DMS desktop environment
- [Niri](https://github.com/YaLTeR/niri) - Scrollable-tiling Wayland compositor  
- [Quickshell](https://github.com/outfoxxed/quickshell) - QtQuick desktop shell toolkit  
- [Matugen](https://github.com/InioX/matugen) - Material You color generator  
- [Cliphist](https://github.com/sentriz/cliphist) - Wayland clipboard manager  
- [Danksearch](https://github.com/AvengeMedia/danksearch) - Application launcher  
- [Dgop](https://github.com/AvengeMedia/dgop) - Package manager integration

## Troubleshooting

**Verify installation:**
```bash
# Check packages
dpkg -l | grep -E "(niri|quickshell|matugen|cliphist)"  # Debian/Ubuntu
rpm -qa | grep -E "(niri|quickshell|matugen|cliphist)"  # OpenSUSE

# Verify versions
niri --version
quickshell --version
```

**Repository issues:**
```bash
sudo apt update --fix-missing          # Debian/Ubuntu
sudo zypper refresh && sudo zypper clean  # OpenSUSE
```

## Build Status

- **DMS Stable**: [home:AvengeMedia:dms](https://build.opensuse.org/project/show/home:AvengeMedia:dms)
- **DMS Nightly**: [home:AvengeMedia:dms-git](https://build.opensuse.org/project/show/home:AvengeMedia:dms-git)
- **Dependencies**: [home:AvengeMedia:danklinux](https://build.opensuse.org/project/show/home:AvengeMedia:danklinux)
- **Launchpad**: [ppa:avengemedia/danklinux](https://launchpad.net/~avengemedia/+archive/ubuntu/danklinux)

## Contributing

Packaging specs and automation maintained in this repository.

- **Packaging issues**: [GitHub Issues](https://github.com/AvengeMedia/danklinux/issues)  
- **Upstream bugs**: Report to respective project repositories

## License

Packages retain their upstream licenses: Niri (GPL-3.0), Quickshell (LGPL-3.0), Matugen (GPL-2.0), Cliphist (GPL-3.0).
