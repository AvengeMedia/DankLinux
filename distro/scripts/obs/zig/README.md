# Zig Binary Repackaging for OBS

## Overview

The Zig packages (zig14, zig15) are **fundamentally different** from other packages in the danklinux repository:

- **Other packages**: Clone source code, compile, vendor dependencies
- **Zig packages**: Download pre-built official binaries, repackage them

This approach is necessary because:
1. Zig requires itself to build (bootstrap problem)
2. Official binaries are optimized and tested
3. Faster builds (no compilation)
4. Consistent with how most distros package Zig

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Zig Build Workflow                        │
└─────────────────────────────────────────────────────────────┘

1. Download Official Binaries (ziglang.org)
   ├─ zig-linux-x86_64-0.14.0.tar.xz (45MB)
   └─ zig-linux-aarch64-0.14.0.tar.xz (45MB)

2. Create Distribution-Specific Packages
   ├─ Debian (3.0 quilt format)
   │  ├─ orig.tar.xz (90MB with both binaries)
   │  ├─ debian.tar.xz (packaging files)
   │  └─ .dsc (auto-generated checksums)
   │
   └─ OpenSUSE (RPM format)
      ├─ .tar.gz (90MB with both binaries)
      ├─ .spec (build instructions)
      └─ -rpmlintrc (suppress false positives)

3. Upload to OBS

4. OBS Builds for Each Platform
   ├─ Extracts binary for current architecture
   ├─ Installs to /usr/lib/zig-VERSION/
   └─ Creates symlink /usr/bin/zig-VERSION
```

## Build Scripts

### build-zig-debian.sh

**Purpose**: Create Debian source packages with proper 3.0 (quilt) format

**How it works**:
```bash
# 1. Download binaries
curl ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz
curl ziglang.org/download/0.14.0/zig-linux-aarch64-0.14.0.tar.xz

# 2. Create orig.tar.xz (upstream source)
tar -cJf zig14_0.14.0.orig.tar.xz \
    zig14-0.14.0/
    ├─ zig-linux-x86_64-0.14.0.tar.xz
    └─ zig-linux-aarch64-0.14.0.tar.xz

# 3. Add debian/ directory and run dpkg-source
cd zig14-0.14.0/
cp -r distro/debian/zig/zig14/debian .
dpkg-source -b .

# 4. Output files ready for upload
zig14_0.14.0.orig.tar.xz       # Both arch binaries
zig14_0.14.0-1.debian.tar.xz   # Packaging files
zig14_0.14.0-1.dsc             # Checksums (auto-generated)
```

**Key concepts**:
- **3.0 (quilt)** format separates upstream (orig.tar.xz) from Debian (debian.tar.xz)
- **Both architectures** in single orig.tar.xz
- **debian/rules** extracts appropriate binary based on DEB_HOST_ARCH
- **dpkg-source** automatically generates correct checksums
- **No network** needed during OBS build (binaries included)

### build-zig-opensuse.sh

**Purpose**: Create OpenSUSE RPM source packages

**How it works**:
```bash
# 1. Download binaries
curl ziglang.org/download/0.14.0/zig-linux-x86_64-0.14.0.tar.xz
curl ziglang.org/download/0.14.0/zig-linux-aarch64-0.14.0.tar.xz

# 2. Create simple tarball at root level
tar -czf zig14-0.14.0.tar.gz \
    zig-linux-x86_64-0.14.0.tar.xz \
    zig-linux-aarch64-0.14.0.tar.xz

# 3. Copy .spec and -rpmlintrc files
cp distro/opensuse/zig/zig14.spec .
cp distro/opensuse/zig/zig14-rpmlintrc .

# 4. Output files ready for upload
zig14-0.14.0.tar.gz    # Both arch binaries at root
zig14.spec             # Build instructions
zig14-rpmlintrc        # Suppress linter warnings
```

**Key concepts**:
- **Simple .tar.gz** with binaries at root level
- **%setup -q -c** creates directory and extracts
- **%prep** section extracts binary for current %{_arch}
- **No compilation** in %build section
- **rpmlintrc** suppresses false positives about stdlib .h/.cpp files

## Comparison with Normal Packages

### Normal Package Build Flow
```
obs-build-debian.sh/obs-build-opensuse.sh
↓
Clone from GitHub
↓
Vendor dependencies (Rust/Go)
↓
Create source tarball
↓
Upload to OBS
↓
OBS compiles from source
```

### Zig Package Build Flow
```
build-zig-debian.sh/build-zig-opensuse.sh
↓
Download official binaries from ziglang.org
↓
Repackage with both architectures
↓
Upload to OBS
↓
OBS extracts appropriate binary (no compilation)
```

## Why Not Integrate with obs-orchestrator.sh?

The zig packages are intentionally **separate** from the main automation:

1. **Different source**: ziglang.org instead of GitHub
2. **Infrequent updates**: Zig releases slowly (months between versions)
3. **Manual verification**: Want to test each Zig release before packaging
4. **Dependency for other packages**: Ghostty depends on zig14
5. **Multiple versions**: Need both zig14 and zig15 simultaneously

## File Organization

```
distro/
├─ debian/zig/
│  ├─ zig14/debian/
│  │  ├─ source/format      # "3.0 (quilt)"
│  │  ├─ control            # Package metadata
│  │  ├─ rules              # Build instructions
│  │  ├─ changelog          # Version history
│  │  └─ copyright          # License info
│  └─ zig15/debian/         # Same structure
│
├─ opensuse/zig/
│  ├─ zig14.spec            # RPM build instructions
│  ├─ zig14-rpmlintrc       # Suppress false positives
│  ├─ zig15.spec
│  └─ zig15-rpmlintrc
│
└─ scripts/obs/zig/
   ├─ build-zig-debian.sh   # Build Debian packages
   ├─ build-zig-opensuse.sh # Build OpenSUSE packages
   └─ README.md            # This file
```

## Usage

### Building Packages

```bash
cd distro/scripts/obs/zig

# Build Debian packages
./build-zig-debian.sh zig14 /tmp/zig14-debian
./build-zig-debian.sh zig15 /tmp/zig15-debian

# Build OpenSUSE packages
./build-zig-opensuse.sh zig14 /tmp/zig14-opensuse
./build-zig-opensuse.sh zig15 /tmp/zig15-opensuse
```

### Uploading to OBS

**Option 1**: Upload both distros together
```bash
cd distro/scripts/obs

# Copy both Debian and OpenSUSE files into one directory
mkdir /tmp/zig14-complete
cp /tmp/zig14-debian/* /tmp/zig14-complete/
cp /tmp/zig14-opensuse/* /tmp/zig14-complete/

# Upload with --distro=both
./obs-upload.sh --distro=both zig14 /tmp/zig14-complete
```

**Option 2**: Upload separately (not recommended - files get removed)
```bash
# Don't do this - uploading one distro removes the other's files!
./obs-upload.sh --distro=debian zig14 /tmp/zig14-debian
./obs-upload.sh --distro=opensuse zig14 /tmp/zig14-opensuse
```

### Checking Build Status

```bash
# Check all builds
osc results home:AvengeMedia:danklinux zig14
osc results home:AvengeMedia:danklinux zig15

# Check specific build log
osc buildlog home:AvengeMedia:danklinux zig14 Debian_Unstable x86_64
osc buildlog home:AvengeMedia:danklinux zig14 openSUSE_Tumbleweed x86_64
```

## Updating to New Zig Versions

When a new Zig version is released:

### For Minor Updates (e.g., 0.14.0 → 0.14.1)
```bash
# 1. Update version in scripts (build-zig-debian.sh, build-zig-opensuse.sh)
ZIG_VERSION="0.14.1"

# 2. Update distro packaging
# - debian/zig/zig14/debian/changelog
# - opensuse/zig/zig14.spec changelog

# 3. Rebuild and test locally
./build-zig-debian.sh zig14 /tmp/test
tar -tf /tmp/test/zig14_0.14.1.orig.tar.xz  # Verify structure

# 4. Upload to OBS
./obs-upload.sh --distro=both zig14 /tmp/test
```

### For Major Updates (e.g., 0.16.0)
```bash
# 1. Create new package directories
mkdir -p distro/debian/zig/zig16/debian
mkdir -p distro/opensuse/zig/

# 2. Copy and modify from zig14/zig15
# - Update version numbers
# - Update package names (zig16)
# - Update install paths (/usr/lib/zig-0.16.0)

# 3. Update build scripts to support zig16
# 4. Build and upload as new package
```

## Troubleshooting

### Debian: "Cannot open: No such file or directory"
**Problem**: Binary tarballs not found during build

**Cause**: debian/rules clean removed the .tar.xz files

**Solution**: Ensure override_dh_auto_clean only removes extracted directories:
```makefile
override_dh_auto_clean:
	# Don't remove *.tar.xz files!
	rm -rf zig-linux-x86_64-$(ZIG_VERSION) zig-cache
	dh_auto_clean
```

### OpenSUSE: rpmlint errors about devel files
**Problem**: "devel-file-in-non-devel-package" errors

**Cause**: Zig stdlib includes .h and .cpp files

**Solution**: rpmlintrc file filters these:
```
addFilter("zig14.* devel-file-in-non-devel-package .*/zig-0.14.0/lib/")
```

### .dsc checksum mismatches
**Problem**: "MD5 sum mismatch" or "Size mismatch"

**Cause**: Manually editing files after dpkg-source generated .dsc

**Solution**: Never edit files after dpkg-source runs. Always let dpkg-source generate the .dsc

## Integration with Ghostty

Ghostty now uses the zig14 package instead of downloading Zig:

### Debian
```debian
Build-Depends: zig14
```

### OpenSUSE
```spec
BuildRequires: zig14
```

This removes the need for wget/curl in Ghostty builds and ensures consistent Zig versions.

## Related Documentation

- `distro/opensuse/GHOSTTY-BUILD-NOTES.md` - Ghostty's integration with zig14
- `distro/scripts/obs/usage.md` - General OBS workflow
- `distro/OBS-REPOSITORY-SETUP.md` - OBS project configuration
