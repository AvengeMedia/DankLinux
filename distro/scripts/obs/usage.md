# OBS Build Automation (v2)

Modular OBS automation system

## Key Features

- **Zero false positives**: Version normalization strips `.db` suffixes before comparison
- **Centralized config**: Single `obs-packages.yaml` replaces scattered hardcoded lists
- **Hash integrity**: Verifies source matches upstream, ensures identical rebuilds
- **Robust APIs**: Exponential backoff retry (2s, 4s, 8s), 15-min caching

## Architecture

```
distro/
├── scripts/obs/
│   ├── lib/                      # Core libraries
│   │   ├── common.sh             # Logging, errors, utilities
│   │   ├── version.sh            # Version parsing
│   │   ├── package-config.sh     # Config loader
│   │   ├── api.sh                # GitHub/OBS APIs
│   │   └── hash.sh               # Hash verification
│   ├── obs-check-updates.sh      # Update detection
│   ├── obs-build-debian.sh       # Debian builder
│   ├── obs-build-opensuse.sh     # OpenSUSE builder
│   ├── obs-upload.sh             # Upload coordinator
│   ├── obs-orchestrator.sh       # Main CLI
│   └── obs-update-prjconf.sh     # Project config updater
├── config/
│   └── obs-packages.yaml         # Package definitions
└── obs-project.conf              # OBS prjconf
```

## Usage

### Check for Updates

```bash
# Check all packages (default)
./obs-check-updates.sh

# Check specific package
./obs-check-updates.sh niri-git

# Check git packages only
./obs-check-updates.sh all-git

# JSON output for automation
./obs-check-updates.sh --json all-git
```

### Build and Upload

```bash
# Auto-detect version and build latest (both distros)
./obs-orchestrator.sh ghostty

# Rebuild with incremented .db suffix
./obs-orchestrator.sh ghostty 2
./obs-orchestrator.sh niri-git 3

# Build specific distro
./obs-orchestrator.sh ghostty 2 debian
./obs-orchestrator.sh niri-git 2 opensuse

# Build all packages with updates
./obs-orchestrator.sh all

# Check only (don't build)
./obs-orchestrator.sh --check-only all
```

### GitHub Actions

Workflow: `.github/workflows/run-obs-v2.yml`

- Runs every 6 hours, checks all packages
- Auto-builds on updates
- Manual triggers: package name, rebuild number, distro

## Package Configuration

All packages are defined in `distro/config/obs-packages.yaml`:

```yaml
packages:
  niri-git:
    type: git
    upstream:
      repo: YaLTeR/niri
      branch: main
    base_version:
      from_stable: niri
      fallback: "25.11"
    distros: [debian, opensuse]
    build:
      language: rust
      vendor_deps: true
```

**Adding packages:**

1. Add to `obs-packages.yaml`
2. Create `debian/<package>/debian/` and `opensuse/<package>.spec`
3. Run `./obs-orchestrator.sh <package>`

## Version Format

**Git:** `BASE+gitCOUNT.HASH[.dbN]` (e.g., `25.11+git2576.7c089857.db2`)
**Stable:** `VERSION[.dbN]` (e.g., `0.8.db2`)

## Rebuilds

Same source, incremented `.db` suffix. Use for packaging fixes, dependency updates, or build system testing.

```bash
./obs-orchestrator.sh --rebuild=2 niri-git
# 25.11+git2576.7c089857.db1 → 25.11+git2576.7c089857.db2
```

## Packages

**Stable:** cliphist, danksearch, dgop, ghostty, matugen, niri (Debian), quickshell, xwayland-satellite
**Git:** niri-git, quickshell-git, xwayland-satellite-git
**Pinned:** quickshell (stable) uses pins.yaml for commit pinning

## Testing

```bash
# Check for updates without building
./obs-check-updates.sh all

# Check with verbose output
./obs-check-updates.sh --verbose niri-git
```

## Migration

Replaced 1,713-line monolith with modular system (5 libs, 5 scripts, 1 config).

## Troubleshooting

**Stale updates:** `rm -rf ~/.cache/obs-automation && ./obs-check-updates.sh <package>`
**Hash mismatch:** Retry build with `./obs-orchestrator.sh <package>`
**OBS conflicts:** `cd ~/.cache/osc-checkouts/.../package && osc revert * && osc up`
**Rate limit:** Set `GITHUB_TOKEN` environment variable

## OBS Configuration

Project config in `distro/obs-project.conf` fixes dependency conflicts. Apply changes:

```bash
./obs-update-prjconf.sh
```

## Environment

- `GITHUB_TOKEN` - GitHub API (rate limit)
- `OBS_USERNAME`, `OBS_PASSWORD` - OBS auth
- `OBS_PROJECT` - Project name (default: `home:AvengeMedia:danklinux`)
- `DEBUG` - Debug logging

## Links

- **OBS Project**: <https://build.opensuse.org/project/show/home:AvengeMedia:danklinux>
- **Logs**: `/tmp/obs-build-*/build.log`
