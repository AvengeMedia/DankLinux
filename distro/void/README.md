# Void Linux packaging

XBPS templates for the DankLinux tools that aren't yet in the Void repositories.
Each builds from source from its upstream release.

| Package | Binary | Upstream | Description |
| --- | --- | --- | --- |
| `dgop` | `dgop` | [AvengeMedia/dgop](https://github.com/AvengeMedia/dgop) | System monitor / telemetry CLI |
| `danksearch` | `dsearch` | [AvengeMedia/danksearch](https://github.com/AvengeMedia/danksearch) | Fast filesystem search |
| `dankcalendar` | `dcal` | [AvengeMedia/dankcalendar](https://github.com/AvengeMedia/dankcalendar) | Calendar app (Local, Google, CalDAV, iCloud) |

`dgop` and `danksearch` integrate with DankMaterialShell; `dankcalendar` is a
standalone app. The `dms` and `dms-greeter` packages live in the
[DankMaterialShell repo](https://github.com/AvengeMedia/DankMaterialShell/tree/master/distro/void).

## Distribution

Until these packages are officially merged upstream in the Void Linux
repositories, you can install them from our Cloudflare R2-backed XBPS
repository at `void.danklinux.com`.

> **Repository migration:** the former GitHub Pages repository will be frozen
> for 14 days at cutover. Its retirement date will be announced when the
> snapshot is frozen. Replace any existing `avengemedia.github.io` entry with
> the URL below.

### Using the Self-Hosted Repository

Add the repository configuration to your system:

```sh
echo "repository=https://void.danklinux.com/danklinux/current" | sudo tee /etc/xbps.d/danklinux.conf
```

Synchronize repositories and install the package(s):

```sh
sudo xbps-install -S dgop danksearch dankcalendar
```

*Note: On the first sync, `xbps-install` will output our signing key fingerprint and ask you to type `y` to trust and import it. Verify that the key matches our official signing fingerprint.*

## Build from Source

In a [void-packages](https://github.com/void-linux/void-packages) checkout, copy
each `srcpkgs/<pkg>` directory in, then:

```sh
./xbps-src pkg dgop
./xbps-src pkg danksearch
./xbps-src pkg dankcalendar
sudo xbps-install --repository=hostdir/binpkgs dankcalendar
```


To lint a template, use `xlint srcpkgs/dankcalendar/template` (from the `xtools`
package). These are Go packages and need Go ≥ 1.25 in the build environment.
