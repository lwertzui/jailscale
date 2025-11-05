#!/bin/sh

HSVER=$(curl -sI https://github.com/juanfont/headscale/releases/latest \
  | grep -i '^location:' \
  | awk -F/ '{print $NF}' \
  | tr -d '\r')

JAILDIR="/usr/jails"

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "You must be root to do this." >&2
    exit 100
fi

echo "Creating jail directory at: $JAILDIR/headscale"
mkdir -pv "$JAILDIR/headscale"

echo "Installing FreeBSD base system into $JAILDIR/headscale"

# === Jail bootstrap ===
export BSDINSTALL_CHROOT="$JAILDIR/headscale"
export DISTRIBUTIONS="base.txz"

# Automatically detect release version
REL="$(freebsd-version | cut -d- -f1)"
export BSDINSTALL_DISTSITE="https://download.freebsd.org/ftp/releases/amd64/${REL}-RELEASE"

# Fetch and extract base sets (non-interactive)
bsdinstall distfetch
bsdinstall distextract

# === Enable jails in rc.conf if not already ===
if ! grep -q '^jail_enable="YES"' /etc/rc.conf; then
    echo 'enabling jails'
    echo 'jail_enable="YES"' >> /etc/rc.conf
fi

if ! grep -q '^jail_parallel_start="YES"' /etc/rc.conf; then
    echo 'enabling jail_parallel_start'
    echo 'jail_parallel_start="YES"' >> /etc/rc.conf
fi

if ! grep -q '^\s*headscale\s*{' /etc/jail.conf; then
    echo "adding jail 'headscale' to /etc/jail.conf"
    cat <<'EOF' >> /etc/jail.conf
headscale {
    path = /usr/jails/headscale;
    host.hostname = headscale.localdomain;
    exec.start = "/bin/sh /etc/rc";
    exec.stop  = "/bin/sh /etc/rc.shutdown";
    persist;
}
EOF
else
    echo "Jail 'headscale' already exists in /etc/jail.conf"
fi

echo "Base jail installed successfully at: $JAILDIR/headscale"

wget --output-document=$JAILDIR/headscale/usr/bin/headscale \
https://github.com/juanfont/headscale/releases/download/v$HSVER/headscale_$HSVER_freebsd_amd64

chmod +x $JAILDIR/headscale/usr/bin/headscale

# Need to substitute with adduser, gonna finish tomorrow
#sudo useradd \
# --create-home \
# --home-dir /var/lib/headscale/ \
# --system \
# --user-group \
# --shell /usr/sbin/nologin \
# headscale
