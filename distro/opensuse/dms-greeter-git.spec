# DMS Greeter - git snapshots (openSUSE/OBS). Conflicts with stable, never Obsoletes it.
# Source tarball is prepared offline-ready by obs-build-opensuse.sh (vendor, submodule, .go-toolchain).

%global debug_package %{nil}
%global pkg_summary DMS Greeter for greetd (git)

Name:           dms-greeter-git
Epoch:          2
Version:        2.0.0+git96.920def34
Release:        1%{?dist}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-greeter

Source0:        dms-greeter-git-source.tar.gz

BuildRequires:  make
BuildRequires:  systemd-rpm-macros

Requires:       greetd
Requires:       (quickshell-git or quickshell)
Requires(pre):  /usr/sbin/useradd
Requires(pre):  /usr/sbin/groupadd

Provides:       dms-greeter = %{epoch}:%{version}-%{release}
Conflicts:      dms-greeter

Recommends:     policycoreutils-python-utils
Recommends:     acl
Suggests:       niri
Suggests:       hyprland
Suggests:       sway

%description
DMS Greeter is a greetd login screen with the Dux Shell aesthetic.
This git package builds from the tip of the dux-greeter repository.
A single Go binary with the Quickshell UI embedded; the UI is extracted
to the greeter cache directory at startup.

Supports multiple compositors including Niri, Hyprland, Mango, and Sway with
session selection, user authentication, and dynamic theming synced from
Dux Shell.

Conflicts with the stable dms-greeter package; both install /usr/bin/dms-greeter.
Switch explicitly (e.g. zypper remove dms-greeter && zypper install dms-greeter-git).

%prep
%setup -q -n dms-greeter-git-source
test -d core/vendor || { echo "ERROR: vendored Go dependencies missing from source tarball"; exit 1; }
test -e quickshell/DCommon/Widgets/DIcon.qml || { echo "ERROR: DCommon submodule content missing from source tarball"; exit 1; }

%build
# OBS is offline; use the bundled Go toolchain.
case "$(uname -m)" in
    x86_64) GO_HOST_ARCH=amd64 ;;
    aarch64) GO_HOST_ARCH=arm64 ;;
    *) echo "unsupported architecture: $(uname -m)"; exit 1 ;;
esac
export PATH="$(pwd)/.go-toolchain/${GO_HOST_ARCH}/go/bin:${PATH}"
export GOTOOLCHAIN=local
export GOFLAGS="-mod=vendor"

export HOME=%{_builddir}/go-home
export GOCACHE=%{_builddir}/go-cache
export GOMODCACHE=%{_builddir}/go-mod
mkdir -p $HOME $GOCACHE $GOMODCACHE

go version

VERSION="%{version}"
COMMIT="$(echo %{version} | sed -n 's/.*\.\([a-f0-9]\{8\}\)$/\1/p')"
make -C core build VERSION="$VERSION" COMMIT="${COMMIT:-unknown}"

%install
install -Dm755 core/bin/dms-greeter %{buildroot}%{_bindir}/dms-greeter

install -d %{buildroot}%{_datadir}/bash-completion/completions
install -d %{buildroot}%{_datadir}/zsh/site-functions
install -d %{buildroot}%{_datadir}/fish/vendor_completions.d
core/bin/dms-greeter completion bash > %{buildroot}%{_datadir}/bash-completion/completions/dms-greeter
core/bin/dms-greeter completion zsh > %{buildroot}%{_datadir}/zsh/site-functions/_dms-greeter
core/bin/dms-greeter completion fish > %{buildroot}%{_datadir}/fish/vendor_completions.d/dms-greeter.fish

install -Dpm0644 assets/systemd/sysusers-dms-greeter.conf %{buildroot}%{_sysusersdir}/dms-greeter.conf
install -Dpm0644 assets/systemd/tmpfiles-dms-greeter.conf %{buildroot}%{_tmpfilesdir}/dms-greeter.conf

install -Dm644 LICENSE %{buildroot}%{_docdir}/dms-greeter/LICENSE
install -Dm644 README.md %{buildroot}%{_docdir}/dms-greeter/README.md
install -d %{buildroot}%{_docdir}/dms-greeter/examples
install -m644 assets/examples/* %{buildroot}%{_docdir}/dms-greeter/examples/

install -dm755 %{buildroot}%{_sharedstatedir}/greeter
install -dm750 %{buildroot}%{_localstatedir}/cache/dms-greeter

%files
%dir %{_docdir}/dms-greeter
%license %{_docdir}/dms-greeter/LICENSE
%doc %{_docdir}/dms-greeter/README.md
%doc %{_docdir}/dms-greeter/examples
%{_bindir}/dms-greeter
%{_datadir}/bash-completion/completions/dms-greeter
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_dms-greeter
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/dms-greeter.fish
%{_sysusersdir}/dms-greeter.conf
%{_tmpfilesdir}/dms-greeter.conf
%dir %attr(0755,greeter,greeter) %{_sharedstatedir}/greeter
%dir %attr(0750,greeter,greeter) %{_localstatedir}/cache/dms-greeter

%pre
# Create greeter user/group if they don't exist
getent group greeter >/dev/null || groupadd -r greeter
getent passwd greeter >/dev/null || \
    useradd -r -g greeter -d %{_sharedstatedir}/greeter -s /bin/bash \
    -c "System Greeter" greeter
exit 0

%post
# SELinux contexts for current Tumbleweed/Leap when SELinux tooling is installed
if [ -x /usr/sbin/semanage ] && [ -x /usr/sbin/restorecon ]; then
    semanage fcontext -a -t bin_t '%{_bindir}/dms-greeter' >/dev/null 2>&1 || true
    restorecon %{_bindir}/dms-greeter >/dev/null 2>&1 || true
    semanage fcontext -a -t user_home_dir_t '%{_sharedstatedir}/greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_sharedstatedir}/greeter >/dev/null 2>&1 || true
    semanage fcontext -a -t cache_home_t '%{_localstatedir}/cache/dms-greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_localstatedir}/cache/dms-greeter >/dev/null 2>&1 || true
    restorecon %{_sysconfdir}/pam.d/greetd >/dev/null 2>&1 || true
fi

# Resolve greeter runtime account/group for distro differences
GREETER_USER=$(sed -n '/^\[default_session\]/,/^\[/s/^user *= *"\([^"]*\)".*/\1/p' /etc/greetd/config.toml 2>/dev/null | head -n1)
if [ -z "$GREETER_USER" ] || ! getent passwd "$GREETER_USER" >/dev/null 2>&1; then
    GREETER_USER="greeter"
    for candidate in greeter greetd _greeter; do
        if getent passwd "$candidate" >/dev/null 2>&1; then
            GREETER_USER="$candidate"
            break
        fi
    done
fi

GREETER_GROUP="$GREETER_USER"
if ! getent group "$GREETER_GROUP" >/dev/null 2>&1; then
    for candidate in greeter greetd _greeter; do
        if getent group "$candidate" >/dev/null 2>&1; then
            GREETER_GROUP="$candidate"
            break
        fi
    done
fi

# Ensure proper ownership of greeter directories
chown -R "$GREETER_USER:$GREETER_GROUP" %{_localstatedir}/cache/dms-greeter 2>/dev/null || true
chown -R "$GREETER_USER:$GREETER_GROUP" %{_sharedstatedir}/greeter 2>/dev/null || true

# Verify PAM configuration
PAM_CONFIG="/etc/pam.d/greetd"
write_greetd_pam_config() {
    # openSUSE and Debian families usually expose PAM stacks as common-*
    if [ -f /etc/pam.d/common-auth ] && [ -f /etc/pam.d/common-account ] && [ -f /etc/pam.d/common-password ] && [ -f /etc/pam.d/common-session ]; then
        cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       include     common-auth
account    required    pam_nologin.so
account    include     common-account
password   include     common-password
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     common-session
PAM_EOF
        return
    fi

    # Fedora/RHEL style system-auth/postlogin stack
    if [ -f /etc/pam.d/system-auth ]; then
        if [ -f /etc/pam.d/postlogin ]; then
            cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       substack    system-auth
auth       include     postlogin
account    required    pam_nologin.so
account    include     system-auth
password   include     system-auth
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     system-auth
session    include     postlogin
PAM_EOF
        else
            cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       include     system-auth
account    required    pam_nologin.so
account    include     system-auth
password   include     system-auth
session    required    pam_loginuid.so
session    optional    pam_keyinit.so force revoke
session    include     system-auth
PAM_EOF
        fi
        return
    fi

    # Last-resort conservative fallback
    cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       required    pam_unix.so nullok
account    required    pam_unix.so
password   required    pam_unix.so nullok sha512
session    required    pam_unix.so
PAM_EOF
}

if [ ! -f "$PAM_CONFIG" ]; then
    write_greetd_pam_config
    chmod 644 "$PAM_CONFIG"
    [ "$1" -eq 1 ] && echo "Created PAM configuration for greetd"
else
    NEEDS_PAM_UPDATE=0
    if grep -q "common-auth" "$PAM_CONFIG"; then
        if [ ! -f /etc/pam.d/common-auth ]; then
            NEEDS_PAM_UPDATE=1
        fi
    elif grep -q "system-auth" "$PAM_CONFIG"; then
        if [ ! -f /etc/pam.d/system-auth ]; then
            NEEDS_PAM_UPDATE=1
        fi
    else
        NEEDS_PAM_UPDATE=1
    fi

    if [ "$NEEDS_PAM_UPDATE" -eq 1 ]; then
        cp "$PAM_CONFIG" "$PAM_CONFIG.backup-dms-greeter"
        write_greetd_pam_config
        chmod 644 "$PAM_CONFIG"
        [ "$1" -eq 1 ] && echo "Updated PAM configuration (old config backed up to $PAM_CONFIG.backup-dms-greeter)"
    fi
fi

# Auto-configure greetd config
GREETD_CONFIG="/etc/greetd/config.toml"
CONFIG_STATUS="Not modified (already configured)"

COMPOSITOR=""
for candidate in niri Hyprland sway; do
    if command -v "$candidate" >/dev/null 2>&1; then
        case "$candidate" in
            Hyprland)
                COMPOSITOR="hyprland"
                ;;
            *)
                COMPOSITOR="$candidate"
                ;;
        esac
        break
    fi
done

if [ ! -f "$GREETD_CONFIG" ]; then
    mkdir -p /etc/greetd
    if [ -n "$COMPOSITOR" ]; then
        cat > "$GREETD_CONFIG" << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "GREETER_USER_PLACEHOLDER"
command = "/usr/bin/dms-greeter --command COMPOSITOR_PLACEHOLDER"
GREETD_EOF
        sed -i "s|GREETER_USER_PLACEHOLDER|$GREETER_USER|" "$GREETD_CONFIG"
        sed -i "s|COMPOSITOR_PLACEHOLDER|$COMPOSITOR|" "$GREETD_CONFIG"
        CONFIG_STATUS="Created new config with $COMPOSITOR ✓"
    else
        cat > "$GREETD_CONFIG" << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "GREETER_USER_PLACEHOLDER"
command = "agreety --cmd /bin/login"
GREETD_EOF
        sed -i "s|GREETER_USER_PLACEHOLDER|$GREETER_USER|" "$GREETD_CONFIG"
        CONFIG_STATUS="Created safe fallback config (no supported compositor detected)"
    fi
elif ! grep -q "dms-greeter" "$GREETD_CONFIG"; then
    if [ -n "$COMPOSITOR" ]; then
        BACKUP_FILE="${GREETD_CONFIG}.backup-$(date +%%Y%%m%%d-%%H%%M%%S)"
        cp "$GREETD_CONFIG" "$BACKUP_FILE" 2>/dev/null || true
        sed -i "/^\[default_session\]/,/^\[/ s|^command =.*|command = \"/usr/bin/dms-greeter --command $COMPOSITOR\"|" "$GREETD_CONFIG"
        sed -i "/^\[default_session\]/,/^\[/ s|^user =.*|user = \"$GREETER_USER\"|" "$GREETD_CONFIG"
        CONFIG_STATUS="Updated existing config (backed up) with $COMPOSITOR ✓"
    else
        CONFIG_STATUS="Skipped dms-greeter command update (no supported compositor detected)"
    fi
fi

# Set graphical.target as default
CURRENT_TARGET=$(systemctl get-default 2>/dev/null || echo "unknown")
if [ "$CURRENT_TARGET" != "graphical.target" ]; then
    systemctl set-default graphical.target >/dev/null 2>&1 || true
    TARGET_STATUS="Set to graphical.target (was: $CURRENT_TARGET) ✓"
else
    TARGET_STATUS="Already graphical.target ✓"
fi

if [ "$1" -eq 1 ]; then
cat << 'EOF'

=========================================================================
        DMS Greeter Git Package Installed
=========================================================================

Status:
EOF
echo "    ✓ Greetd config: $CONFIG_STATUS"
echo "    ✓ Default target: $TARGET_STATUS"
cat << 'EOF'
    ✓ Greeter runtime account and directories prepared

Finish setup before rebooting:
1. Enable greetd and prepare runtime permissions/security labels:
     dms-greeter enable

2. Sync your existing DMS theme and settings to the greeter after reboot:
     dms-greeter sync

Verify with: dms-greeter status
Documentation: https://duxlabs.dev/docs/dms-greeter/
=========================================================================

EOF
fi

%postun
if [ "$1" -eq 0 ] && [ -x /usr/sbin/semanage ]; then
    semanage fcontext -d '%{_bindir}/dms-greeter' 2>/dev/null || true
    semanage fcontext -d '%{_sharedstatedir}/greeter(/.*)?' 2>/dev/null || true
    semanage fcontext -d '%{_localstatedir}/cache/dms-greeter(/.*)?' 2>/dev/null || true
fi

%changelog
* Sat Oct 24 2026 Avenge Media <AvengeMedia.US@gmail.com> - 2:2.0.0+git96.920def34-1
- Packaging moved from the dux-greeter repository to dux-packaging
  (version rewritten by obs-build-opensuse.sh on each snapshot)
