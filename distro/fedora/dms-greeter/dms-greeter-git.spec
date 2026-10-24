# DMS Greeter - git snapshots (Fedora/Copr). Conflicts with stable, never Obsoletes it.
# %%global commit/commits/snapdate/tag/common_commit are rewritten by copr-update.sh.

%global debug_package %{nil}

%global commit      26c495da46a4e39e47473b6cb599c7ea6e1290a0
%global commits     98
%global snapdate    20261024
%global tag         2.0.1
# dux-qml-common submodule commit (GitHub archives ship submodules empty)
%global common_commit bb917ea0718892c875ca0955939f63b31dc64e1e

%global pkg_summary DMS Greeter for greetd (git)

Name:           dms-greeter-git
Epoch:          2
Version:        %{tag}+git%{commits}.%(c=%{commit}; echo ${c:0:8})
Release:        1%{?dist}
Summary:        %{pkg_summary}

License:        MIT
URL:            https://github.com/duxlabs-dev/dux-greeter
Source0:        %{url}/archive/%{commit}/dux-greeter-%{commit}.tar.gz
Source1:        https://github.com/duxlabs-dev/dux-qml-common/archive/%{common_commit}/dux-qml-common-%{common_commit}.tar.gz

BuildRequires:  golang
BuildRequires:  git-core
BuildRequires:  make
BuildRequires:  systemd-rpm-macros

Requires:       greetd
Requires:       (quickshell-git or quickshell)
Requires:       policycoreutils-python-utils
Requires(pre):  shadow-utils
Requires(post): shadow-utils

Provides:       dms-greeter = %{epoch}:%{version}-%{release}
Conflicts:      dms-greeter

Recommends:     acl
Suggests:       niri
Suggests:       hyprland
Suggests:       sway

%description
This git package builds from the tip of the dux-greeter repository.

DMS Greeter is a greetd login screen with the Dux Shell aesthetic.
A single Go binary with the Quickshell UI embedded; the UI is extracted
to the greeter cache directory at startup.

Supports multiple compositors including Niri, Hyprland, Mango, and Sway with
session selection, user authentication, and dynamic theming synced from
Dux Shell.

Conflicts with the stable dms-greeter package; both install /usr/bin/dms-greeter.
Switch explicitly with: dnf swap dms-greeter dms-greeter-git

%prep
%autosetup -n dux-greeter-%{commit} -p1
rm -rf dux-qml-common
tar -xzf %{SOURCE1}
mv dux-qml-common-%{common_commit} dux-qml-common
rm -rf quickshell/DCommon
ln -sfn ../dux-qml-common/DCommon quickshell/DCommon
test -e quickshell/DCommon/Widgets/DIcon.qml || { echo "DCommon missing after submodule unpack"; exit 1; }

%build
export GOTOOLCHAIN=auto
export GOFLAGS="-mod=readonly -modcacherw"
export HOME=%{_builddir}/go-home
export GOCACHE=%{_builddir}/go-cache
export GOMODCACHE=%{_builddir}/go-mod
mkdir -p "$HOME" "$GOCACHE" "$GOMODCACHE"
go version

make -C core build \
    VERSION="%{tag}+git%{commits}.%(c=%{commit}; echo ${c:0:8})" \
    COMMIT="%(c=%{commit}; echo ${c:0:8})"

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
%{_datadir}/zsh/site-functions/_dms-greeter
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

# Set SELinux contexts for greeter files on Fedora systems
if [ -x /usr/sbin/semanage ] && [ -x /usr/sbin/restorecon ]; then
    semanage fcontext -a -t bin_t '%{_bindir}/dms-greeter' >/dev/null 2>&1 || true
    restorecon %{_bindir}/dms-greeter >/dev/null 2>&1 || true

    semanage fcontext -a -t user_home_dir_t '%{_sharedstatedir}/greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_sharedstatedir}/greeter >/dev/null 2>&1 || true

    semanage fcontext -a -t cache_home_t '%{_localstatedir}/cache/dms-greeter(/.*)?' >/dev/null 2>&1 || true
    restorecon -R %{_localstatedir}/cache/dms-greeter >/dev/null 2>&1 || true

    restorecon %{_sysconfdir}/pam.d/greetd >/dev/null 2>&1 || true
fi

# follow the greetd user from config.toml like dms-greeter sync does
GREETER_USER=$(sed -n '/^\[default_session\]/,/^\[/s/^user *= *"\([^"]*\)".*/\1/p' /etc/greetd/config.toml 2>/dev/null | head -n1)
if [ -z "$GREETER_USER" ] || ! getent passwd "$GREETER_USER" >/dev/null 2>&1; then
    GREETER_USER=greeter
fi
chown -R "$GREETER_USER:greeter" %{_localstatedir}/cache/dms-greeter 2>/dev/null || true
chown -R greeter:greeter %{_sharedstatedir}/greeter 2>/dev/null || true

PAM_CONFIG="/etc/pam.d/greetd"
if [ ! -f "$PAM_CONFIG" ]; then
    cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       substack    system-auth
auth       include     postlogin

account    required    pam_nologin.so
account    include     system-auth

password   include     system-auth

session    required    pam_selinux.so close
session    required    pam_loginuid.so
session    required    pam_selinux.so open
session    optional    pam_keyinit.so force revoke
session    include     system-auth
session    include     postlogin
PAM_EOF
    chmod 644 "$PAM_CONFIG"
    [ "$1" -eq 1 ] && echo "Created PAM configuration for greetd"
elif ! grep -q "pam_systemd\|system-auth" "$PAM_CONFIG"; then
    cp "$PAM_CONFIG" "$PAM_CONFIG.backup-dms-greeter"
    cat > "$PAM_CONFIG" << 'PAM_EOF'
#%PAM-1.0
auth       substack    system-auth
auth       include     postlogin

account    required    pam_nologin.so
account    include     system-auth

password   include     system-auth

session    required    pam_selinux.so close
session    required    pam_loginuid.so
session    required    pam_selinux.so open
session    optional    pam_keyinit.so force revoke
session    include     system-auth
session    include     postlogin
PAM_EOF
    chmod 644 "$PAM_CONFIG"
    [ "$1" -eq 1 ] && echo "Updated PAM configuration (old config backed up to $PAM_CONFIG.backup-dms-greeter)"
fi

GREETD_CONFIG="/etc/greetd/config.toml"
CONFIG_STATUS="Not modified (already configured)"

COMPOSITOR="niri"
if ! command -v niri >/dev/null 2>&1; then
        if command -v Hyprland >/dev/null 2>&1; then
                COMPOSITOR="hyprland"
        fi
fi

if [ ! -f "$GREETD_CONFIG" ]; then
        mkdir -p /etc/greetd
        cat > "$GREETD_CONFIG" << 'GREETD_EOF'
[terminal]
vt = 1

[default_session]
user = "greeter"
command = "/usr/bin/dms-greeter --command COMPOSITOR_PLACEHOLDER"
GREETD_EOF
        sed -i "s|COMPOSITOR_PLACEHOLDER|$COMPOSITOR|" "$GREETD_CONFIG"
        CONFIG_STATUS="Created new config with $COMPOSITOR ✓"

elif ! grep -q "dms-greeter" "$GREETD_CONFIG"; then
        BACKUP_FILE="${GREETD_CONFIG}.backup-$(date +%%Y%%m%%d-%%H%%M%%S)"
        cp "$GREETD_CONFIG" "$BACKUP_FILE" 2>/dev/null || true

        sed -i "/^\[default_session\]/,/^\[/ s|^command =.*|command = \"/usr/bin/dms-greeter --command $COMPOSITOR\"|" "$GREETD_CONFIG"
        sed -i '/^\[default_session\]/,/^\[/ s|^user =.*|user = "greeter"|' "$GREETD_CONFIG"
        CONFIG_STATUS="Updated existing config (backed up) with $COMPOSITOR ✓"
fi

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
* Sat Oct 24 2026 Avenge Media <AvengeMedia.US@gmail.com> - 2:2.0.1+git97.52f23935-1
- Packaging moved to dux-packaging; build from GitHub commit archives with the
  dux-qml-common submodule fetched separately
