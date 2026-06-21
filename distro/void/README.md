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

## Build & install

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
