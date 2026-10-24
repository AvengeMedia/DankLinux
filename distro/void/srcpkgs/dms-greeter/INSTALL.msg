dms-greeter installed: a single Go binary with the quickshell UI embedded.
It replaces the previous bash wrapper and the /usr/share/quickshell/dms-greeter
tree; existing /etc/greetd/config.toml entries keep working:

    command = "/usr/bin/dms-greeter --command COMPOSITOR"

Void uses elogind for seat management, not seatd. Run `dms-greeter enable`
to set it all up: it enables the dbus and elogind services, makes the greetd
run script wait for them, points greetd at dms-greeter, and adds pam_rundir
to the greetd PAM stack. Without this greetd either never starts (dbus or
elogind not enabled) or shows the stock agreety tty prompt. Sync your shell
theme into the greeter with:

    dms-greeter sync

Requirements not pulled in automatically: a Wayland compositor (niri, hyprland,
sway, …) and a working DRM device (/dev/dri/card*; in a VM, enable virtio-gpu).
