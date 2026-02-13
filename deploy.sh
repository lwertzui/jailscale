#!/bin/sh

HSVER=$(curl -sI https://github.com/juanfont/headscale/releases/latest \
	| grep -i '^location:' \
	| awk -F/ '{print $NF}' \
	| tr -d '\rv')

JAILDIR="/usr/jails"

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

MIRROR = $(mktemp)


REL="$(freebsd-version | cut -d- -f1)"
export BSDINSTALL_DISTSITE="https://$MIRROR/ftp/releases/amd64/${REL}-RELEASE"

if ! [-d "/usr/freebsd-dist"]; then
	mkdir -p '/usr/freebsd-dist'
fi

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

OUT=$(mktemp)
bsddialog --backtitle "Network Setup" \
          --title "CIDR Input" \
          --inputbox "Enter an IP address for Headscale in CIDR format (e.g., 192.168.1.0/24):" \
          10 50 \
          2> "$OUT"

RET=$?   # Return code from bsddialog

# Check if user pressed OK
if [ $RET -eq 0 ]; then
	echo "User entered: $CIDR"
else
	echo "User cancelled."
	exit 1
fi

# Optional: Validate CIDR using a regex
if echo "$CIDR" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$'; then
	CIDR=$(cat "$OUT")
else
	echo "Invalid CIDR format."
	exit 1
fi

rm "$OUT"

if ! grep -q '^\s*headscale\s*{' /etc/jail.conf; then
	echo "adding jail 'headscale' to /etc/jail.conf"
	cat <<'EOF' >> /etc/jail.conf
headscale {
	path = /usr/jails/headscale;
	exec.start = "/bin/sh /etc/rc";
	exec.stop  = "/bin/sh /etc/rc.shutdown";
	exec.clean;
	mount.devfs;
	persist:

	#networking
	host.hostname = headscale.localdomain;
	interface = vtnet0;
	ip4.addr = $CIDR;
	allow.raw_sockets;
}
EOF
else
	echo "Jail 'headscale' already exists in /etc/jail.conf"
fi

echo "Base jail installed successfully at: $JAILDIR/headscale"

wcurl --output=$JAILDIR/headscale/usr/bin/headscale \
https://github.com/juanfont/headscale/releases/download/v${HSVER}/headscale_${HSVER}_freebsd_amd64

wcurl --output=$JAILDIR/headscale/etc/headscale/config.yaml \
https://raw.githubusercontent.com/juanfont/headscale/v${HSVER}/config-example.yaml

cp /etc/resolv.conf $JAILDIR/headscale/etc/resolv.conf

chmod +x $JAILDIR/headscale/usr/bin/headscale

#add user with pw
pw useradd headscale \
	-R  $JAILDIR/headscale/ \
	-d /var/lib/headscale \
	-s /usr/sbin/nologin \
	-c "Headscale system user" \
	-g nogroup \
	-m

mkdir -p $JAILDIR/headscale/etc/headscale
