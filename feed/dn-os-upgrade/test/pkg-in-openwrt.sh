#!/bin/sh
# Inside an OpenWrt rootfs container (feed/dn-os-upgrade/test/pkg-upgrade.test.sh): run the real dn-pkg-upgrade
# against two signed feeds served by uhttpd, with real .ipk packages built here.
PU=/t/feed/dn-os-upgrade/files/usr/sbin/dn-pkg-upgrade
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }
ver() { opkg status "$1" | sed -n 's/^Version: //p'; }

mkdir -p /var/lock /srv/dn_os /srv/other /tmp/k /tmp/b
: > /etc/opkg/distfeeds.conf          # no internet feeds in a test
printf 'src/gz dn_os http://127.0.0.1:8099/dn_os\nsrc/gz other http://127.0.0.1:8099/other\n' > /etc/opkg/customfeeds.conf
usign -G -s /tmp/k/dn.sec -p /tmp/k/dn.pub -c dn;    cp /tmp/k/dn.pub "/etc/opkg/keys/$(usign -F -p /tmp/k/dn.pub)"
usign -G -s /tmp/k/ot.sec -p /tmp/k/ot.pub -c other; cp /tmp/k/ot.pub "/etc/opkg/keys/$(usign -F -p /tmp/k/ot.pub)"
usign -G -s /tmp/k/evil.sec -p /tmp/k/evil.pub -c evil
uhttpd -p 127.0.0.1:8099 -h /srv

# mkipk NAME VERSION OUTDIR: a package with a service whose start/stop are recorded in /tmp/svc.log.
mkipk() {
	d=/tmp/b/$1-$2; rm -rf "$d"; mkdir -p "$d/c" "$d/d/etc/init.d"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test\nDescription: test\n' "$1" "$2" > "$d/c/control"
	cat > "$d/d/etc/init.d/$1" <<EOF
#!/bin/sh /etc/rc.common
START=99
start() { echo "start $1 $2" >> /tmp/svc.log; }
stop() { echo "stop $1" >> /tmp/svc.log; }
EOF
	chmod 755 "$d/d/etc/init.d/$1"
	echo 2.0 > "$d/debian-binary"
	tar -czf "$d/control.tar.gz" -C "$d/c" ./control
	tar -czf "$d/data.tar.gz" -C "$d/d" .
	tar -czf "$3/${1}_${2}_all.ipk" -C "$d" ./debian-binary ./control.tar.gz ./data.tar.gz
}
# index DIR KEY: Packages + Packages.gz + Packages.sig for every .ipk in DIR.
index() {
	: > "$1/Packages"
	for f in "$1"/*.ipk; do
		t=$(mktemp -d); tar -xzf "$f" -C "$t" ./control.tar.gz; tar -xzf "$t/control.tar.gz" -C "$t" ./control
		{ cat "$t/control"; echo "Filename: $(basename "$f")"; echo "Size: $(wc -c < "$f")"
		  echo "SHA256sum: $(sha256sum "$f" | cut -d' ' -f1)"; echo; } >> "$1/Packages"; rm -rf "$t"
	done
	gzip -c "$1/Packages" > "$1/Packages.gz"
	usign -S -m "$1/Packages" -s "/tmp/k/$2.sec" -x "$1/Packages.sig"
}

# Installed: dn-a 1.0 and other-b 1.0, both enabled.
mkipk dn-a 1.0 /tmp/b; mkipk other-b 1.0 /tmp/b
opkg install /tmp/b/dn-a_1.0_all.ipk /tmp/b/other-b_1.0_all.ipk >/dev/null 2>&1
/etc/init.d/dn-a enable; /etc/init.d/other-b enable
# dn_os carries dn-a 1.1 and dn-z 1.0 (not installed); "other" carries other-b 2.0.
mkipk dn-a 1.1 /srv/dn_os; mkipk dn-z 1.0 /srv/dn_os; mkipk other-b 2.0 /srv/other
index /srv/dn_os dn; index /srv/other ot

echo "case 1: --check reports, changes nothing"
out=$(sh "$PU" --check); eq "exit" "$?" 0
eq "reports dn-a 1.0 -> 1.1" "$(echo "$out" | jsonfilter -e '@.upgraded[0].package' -e '@.upgraded[0].from' -e '@.upgraded[0].to' | tr '\n' ' ')" "dn-a 1.0 1.1 "
eq "still 1.0" "$(ver dn-a)" 1.0

echo "case 2: upgrades only dn_os packages, and restarts them"
rm -f /tmp/svc.log
out=$(sh "$PU"); eq "exit" "$?" 0
eq "dn-a upgraded" "$(ver dn-a)" 1.1
eq "other feed's package left alone" "$(ver other-b)" 1.0
eq "uninstalled dn_os package not installed" "$(opkg status dn-z | grep -c Version)" 0
eq "dn-a restarted with its new version" "$(grep -c '^start dn-a 1.1$' /tmp/svc.log)" 1
eq "other-b not restarted" "$(grep -c 'other-b' /tmp/svc.log)" 0
eq "reported" "$(echo "$out" | jsonfilter -e '@.upgraded[0].to')" 1.1

echo "case 3: nothing newer means nothing happens"
rm -f /tmp/svc.log
out=$(sh "$PU"); eq "exit" "$?" 0
eq "empty list" "$(echo "$out" | jsonfilter -e '@.upgraded[*]' | wc -l | tr -d ' ')" 0
eq "no restarts" "$([ -f /tmp/svc.log ] && wc -l < /tmp/svc.log | tr -d ' ' || echo 0)" 0

echo "case 4: a dn_os index signed by an unknown key is refused and installs nothing"
mkipk dn-a 1.2 /srv/dn_os; index /srv/dn_os evil
sh "$PU" 2>/dev/null; eq "exit" "$?" 1
eq "dn-a unchanged" "$(ver dn-a)" 1.1

[ "$fails" -eq 0 ] || { echo "pkg-upgrade.test: $fails failure(s)"; exit 1; }
echo "pkg-upgrade.test: all cases pass"
