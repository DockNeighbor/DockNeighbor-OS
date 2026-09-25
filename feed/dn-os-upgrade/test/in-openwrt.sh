#!/bin/sh
# Inside an OpenWrt rootfs container (feed/dn-os-upgrade/test/upgrade.test.sh): run the real dn-os-upgrade
# against a channel served by uhttpd, signed with throwaway keys. sysupgrade is a stub that records calls,
# so "nothing was flashed" is observable.
UP=/t/feed/dn-os-upgrade/files/usr/sbin/dn-os-upgrade
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }

mkdir -p /var/lock /tmp/sysinfo /etc/dn/os-keys /srv/ch /tmp/stub /tmp/k
echo 'glinet,gl-mt300n-v2' > /tmp/sysinfo/board_name
cat > /etc/dn-release <<EOF
DN_OS_PROFILE=hub-lite
DN_OS_VERSION=0.1.0
DN_OS_CHANNEL_URL=http://127.0.0.1:8099/ch/glinet_gl-mt300n-v2.json
EOF
# The trusted key, and an untrusted one.
usign -G -s /tmp/k/good.sec -p /tmp/k/good.pub -c test; cp /tmp/k/good.pub "/etc/dn/os-keys/$(usign -F -p /tmp/k/good.pub)"
usign -G -s /tmp/k/evil.sec -p /tmp/k/evil.pub -c evil
head -c 200000 /dev/urandom > /srv/ch/image.bin
SHA=$(sha256sum /srv/ch/image.bin | cut -d' ' -f1); SIZE=$(wc -c < /srv/ch/image.bin)
uhttpd -p 127.0.0.1:8099 -h /srv
cat > /tmp/stub/sysupgrade <<'EOF'
#!/bin/sh
echo "$*" >> /tmp/sysupgrade.calls
[ "$1" = -T ] && [ -f /tmp/reject ] && exit 1
exit 0
EOF
chmod 755 /tmp/stub/sysupgrade
export PATH=/tmp/stub:$PATH

# publish VERSION [board] [profile] [sha] [key]
publish() {
	cat > /srv/ch/glinet_gl-mt300n-v2.json <<EOF
{ "profile": "${3:-hub-lite}", "board": "${2:-glinet,gl-mt300n-v2}", "version": "$1", "hubLite": "0.18.2",
  "image": "http://127.0.0.1:8099/ch/image.bin", "sha256": "${4:-$SHA}", "size": $SIZE }
EOF
	usign -S -m /srv/ch/glinet_gl-mt300n-v2.json -s "/tmp/k/${5:-good}.sec" -x /srv/ch/glinet_gl-mt300n-v2.json.sig
	rm -f /tmp/sysupgrade.calls /tmp/reject
}
# grep -c prints 0 AND exits 1 on no match, so no `|| echo 0` here.
flashed() { n=$(grep -c '^/tmp/dn-os-upgrade/image.bin$' /tmp/sysupgrade.calls 2>/dev/null); echo "${n:-0}"; }

echo "case 1: a newer signed release upgrades"
publish 0.1.1
out=$(sh "$UP" check); eq "check exit" "$?" 0
eq "available" "$(echo "$out" | jsonfilter -e @.available)" 0.1.1
eq "upgrade" "$(echo "$out" | jsonfilter -e @.upgrade)" true
sh "$UP" apply >/dev/null; eq "apply exit" "$?" 0
eq "tested first" "$(sed -n 1p /tmp/sysupgrade.calls)" "-T /tmp/dn-os-upgrade/image.bin"
eq "then flashed" "$(flashed)" 1

echo "case 2: the same version is not an upgrade"
publish 0.1.0
eq "upgrade" "$(sh "$UP" check | jsonfilter -e @.upgrade)" false
sh "$UP" apply 2>/dev/null; eq "apply refuses" "$?" 1
eq "nothing flashed" "$(flashed)" 0

echo "case 3: an older, validly signed release can't downgrade"
publish 0.0.9
eq "upgrade" "$(sh "$UP" check | jsonfilter -e @.upgrade)" false
sh "$UP" apply 2>/dev/null; eq "apply refuses" "$?" 1
eq "nothing flashed" "$(flashed)" 0

echo "case 4: a manifest signed by another key is refused"
publish 0.2.0 "" "" "" evil
sh "$UP" check >/dev/null 2>&1; eq "check refuses" "$?" 1
sh "$UP" apply 2>/dev/null; eq "apply refuses" "$?" 1
eq "nothing flashed" "$(flashed)" 0

echo "case 5: a manifest for another board or profile is refused"
publish 0.2.0 "glinet,gl-x750"
sh "$UP" apply 2>/dev/null; eq "other board refused" "$?" 1
publish 0.2.0 "" station
sh "$UP" apply 2>/dev/null; eq "other profile refused" "$?" 1
eq "nothing flashed" "$(flashed)" 0

echo "case 6: an image that doesn't match the signed sha256 is never tested or flashed"
publish 0.2.0 "" "" 0000000000000000000000000000000000000000000000000000000000000000
sh "$UP" apply 2>/dev/null; eq "apply refuses" "$?" 1
eq "no sysupgrade call at all" "$(cat /tmp/sysupgrade.calls 2>/dev/null | wc -l | tr -d ' ')" 0

echo "case 7: an image sysupgrade -T rejects is not flashed"
publish 0.2.0; touch /tmp/reject
sh "$UP" apply 2>/dev/null; eq "apply refuses" "$?" 1
eq "nothing flashed" "$(flashed)" 0

echo "case 8: --detach returns first, then flashes"
publish 0.2.0
sh "$UP" apply --detach >/dev/null; eq "apply exit" "$?" 0
eq "not flashed yet" "$(flashed)" 0
sleep 5
eq "flashed after returning" "$(flashed)" 1

[ "$fails" -eq 0 ] || { echo "upgrade.test: $fails failure(s)"; exit 1; }
echo "upgrade.test: all cases pass"
