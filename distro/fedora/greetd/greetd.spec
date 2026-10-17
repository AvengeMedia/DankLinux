%if 0%{?el10}
%global debug_package %{nil}
%endif

%global         username    greetd
%global         selinuxtype targeted

%bcond_without  selinux

Name:           greetd
Version:        0.10.3
Release:        1%{?dist}
Summary:        A generic greeter daemon

License:        GPL-3.0-only AND Apache-2.0 AND (Apache-2.0 OR BSL-1.0) AND (Apache-2.0 OR MIT) AND MIT AND Unlicense
URL:            https://git.sr.ht/~kennylevinsen/greetd
Source0:        %{url}/archive/%{version}.tar.gz#/greetd-%{version}.tar.gz

Provides:       service(graphical-login) = greetd

BuildRequires:  rust
BuildRequires:  cargo
BuildRequires:  gcc
BuildRequires:  pam-devel
BuildRequires:  sed
BuildRequires:  systemd-rpm-macros

%if %{with selinux}
# Keeps the policy and its dependencies out of containers and other non-SELinux systems
Requires:       (%{name}-selinux = %{version}-%{release} if selinux-policy-%{selinuxtype})
%endif

%description
greetd is a minimal and flexible login manager daemon
that makes no assumptions about what you want to launch.

%if %{with selinux}
%package        selinux
Summary:        SELinux policy for %{name}
BuildArch:      noarch
Requires:       selinux-policy-%{selinuxtype}
Requires(post): selinux-policy-%{selinuxtype}
BuildRequires:  selinux-policy-devel
BuildRequires:  bzip2
BuildRequires:  make
%{?selinux_requires}

%description    selinux
Custom SELinux policy module for %{name}.
%endif

%prep
%autosetup -n greetd-%{version}
sed -i 's/"greeter"/"%{username}"/' config.toml

%build
cargo build --release --bin greetd --bin agreety

%if %{with selinux}
mkdir selinux
pushd selinux
echo 'policy_module(%{name},1.0)' >%{name}.te
cat > %{name}.fc <<'FC'
# SELinux file labels for greetd
# vim: ts=8 noet
/etc/greetd(/.*)?			gen_context(system_u:object_r:xdm_etc_t,s0)
/usr/bin/greetd			--	gen_context(system_u:object_r:xdm_exec_t,s0)
/var/lib/greetd(/.*)?			gen_context(system_u:object_r:xdm_var_lib_t,s0)
/var/run/greetd[^/]*\.sock	-s	gen_context(system_u:object_r:xdm_var_run_t,s0)
/var/run/greetd\.run		--	gen_context(system_u:object_r:xdm_var_run_t,s0)
FC
make -f %{_datadir}/selinux/devel/Makefile %{name}.pp
bzip2 -9 %{name}.pp
popd
%endif

%install
install -Dm755 target/release/greetd   %{buildroot}%{_bindir}/greetd
install -Dm755 target/release/agreety  %{buildroot}%{_bindir}/agreety
install -Dm644 greetd.service          %{buildroot}%{_unitdir}/%{name}.service
install -Dm644 config.toml             %{buildroot}%{_sysconfdir}/%{name}/config.toml
install -d -m750                       %{buildroot}%{_sharedstatedir}/%{name}
install -d -m755 %{buildroot}%{_prefix}/lib/pam.d %{buildroot}%{_sysusersdir} %{buildroot}%{_tmpfilesdir}

# PAM stacks, sysusers and tmpfiles mirror Fedora's greetd package
cat > %{buildroot}%{_prefix}/lib/pam.d/%{name} <<'PAM'
#%%PAM-1.0
auth       substack    system-auth
-auth       optional    pam_gnome_keyring.so
-auth       optional    pam_kwallet5.so
-auth       optional    pam_kwallet.so
-auth       optional    pam_oo7.so
auth       include     postlogin

account    required    pam_sepermit.so
account    required    pam_nologin.so
account    include     system-auth

password   include     system-auth

session    required    pam_selinux.so close
session    required    pam_loginuid.so
session    required    pam_selinux.so open
session    optional    pam_keyinit.so force revoke
session    required    pam_namespace.so
session    include     system-auth
-session    optional    pam_gnome_keyring.so auto_start
-session    optional    pam_kwallet5.so auto_start
-session    optional    pam_kwallet.so auto_start
-session    optional    pam_oo7.so auto_start
session    include     postlogin
PAM

cat > %{buildroot}%{_prefix}/lib/pam.d/%{name}-greeter <<'PAM'
#%%PAM-1.0

# Load environment from /etc/environment and ~/.pam_environment
auth            required pam_env.so

# Always let the greeter start without authentication
auth            required pam_permit.so

# No action required for account management
account         required pam_permit.so

# Can't change password
password        required pam_deny.so

# Setup session
session         required pam_unix.so
session         optional pam_systemd.so
PAM

cat > %{buildroot}%{_sysusersdir}/%{name}.conf <<'SYSUSERS'
#Type Name   ID    GECOS           Home directory  Shell
u     greetd -     "greetd daemon" /var/lib/greetd
SYSUSERS

cat > %{buildroot}%{_tmpfilesdir}/%{name}.conf <<'TMPFILES'
#  Path            Mode User   Group  Age Argument
# Dynamic users/groups are not stable across builds (see also: https://pagure.io/fedora-kde/SIG/issue/87)
Z  /var/lib/greetd -    greetd greetd -   -
TMPFILES

%if %{with selinux}
install -Dm644 selinux/%{name}.pp.bz2 \
    %{buildroot}%{_datadir}/selinux/packages/%{selinuxtype}/%{name}.pp.bz2
%endif

%post
%systemd_post %{name}.service
# Keep the portal from starting in the greeter's user session
XDG_CONFIG_DIR=%{_sharedstatedir}/%{name}/.config
if [ ! -d $XDG_CONFIG_DIR/systemd ]; then
    mkdir -p $XDG_CONFIG_DIR/systemd/user
    ln -sf /dev/null $XDG_CONFIG_DIR/systemd/user/xdg-desktop-portal.service
    chown -R %{username}:%{username} $XDG_CONFIG_DIR
fi
exit 0

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun %{name}.service

%if %{with selinux}
%pre selinux
%selinux_relabel_pre -s %{selinuxtype}

%post selinux
%selinux_modules_install -s %{selinuxtype} %{_datadir}/selinux/packages/%{selinuxtype}/%{name}.pp.bz2
%selinux_relabel_post -s %{selinuxtype}

%postun selinux
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall -s %{selinuxtype} %{name}
    %selinux_relabel_post -s %{selinuxtype}
fi
%endif

%files
%license LICENSE
%doc README.md
%attr(-,%{username},%{username}) %dir %{_sharedstatedir}/%{name}
%dir %{_sysconfdir}/%{name}
%config(noreplace) %{_sysconfdir}/%{name}/config.toml
%{_prefix}/lib/pam.d/%{name}
%{_prefix}/lib/pam.d/%{name}-greeter
%{_bindir}/greetd
%{_bindir}/agreety
%{_sysusersdir}/%{name}.conf
%{_tmpfilesdir}/%{name}.conf
%{_unitdir}/%{name}.service

%if %{with selinux}
%files selinux
%{_datadir}/selinux/packages/%{selinuxtype}/%{name}.pp.*
%ghost %verify(not md5 size mtime) %{_sharedstatedir}/selinux/%{selinuxtype}/active/modules/200/%{name}
%endif

%changelog
* Fri Oct 16 2026 Purian23 <purian23@users.noreply.github.com> - 0.10.3-1
- Initial Copr package release for EL10
- Version 0.10.3
