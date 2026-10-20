# Void Linux packaging

XBPS templates for the Dux Labs tools that aren't yet in the Void repositories.
Each builds from source from its upstream release.

| Package | Binary | Upstream | Description |
| --- | --- | --- | --- |
| `dgop` | `dgop` | [duxlabs-dev/dux-gop](https://github.com/duxlabs-dev/dux-gop) | System monitor / telemetry CLI |
| `danksearch` | `dsearch` | [duxlabs-dev/dux-search](https://github.com/duxlabs-dev/dux-search) | Fast filesystem search |
| `dankcalendar` | `dcal` | [duxlabs-dev/dux-calendar](https://github.com/duxlabs-dev/dux-calendar) | Calendar app (Local, Google, CalDAV, iCloud) |

`dgop` and `danksearch` integrate with Dux Shell; `dankcalendar` is a
standalone app. The `dms` / `dms-git` Void packages live in the
[Dux Shell repo](https://github.com/duxlabs-dev/dux-shell/tree/master/distro/void).
`dms-greeter` packaging lives in
[dank-greeter](https://github.com/duxlabs-dev/dux-greeter/tree/master/distro/void)
and is published to the shared `https://void.danklinux.com/dms/current` repository.

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
