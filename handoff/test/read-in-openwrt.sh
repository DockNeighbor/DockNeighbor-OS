#!/bin/sh
# Inside an OpenWrt rootfs container (handoff/test/read.test.sh): the GL.iNet reader against GL-style configs,
# then the renderer on what it wrote, end to end. Each case starts from a clean config.
READ=/t/handoff/read-glinet.sh
APPLY=/t/feed/dn-handoff/files/usr/libexec/dn-handoff/apply
HASH='$5$abcdefgh$0123456789abcdefghijklmnopqrstuvwxyzABCDEFG'
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }
site() { jsonfilter -i /tmp/site.json -e "$1" 2>/dev/null; }

mkdir -p /etc/dn /tmp/pristine /usr/lib/dn-net /tmp/sysinfo /etc/dropbear
cp /t/feed/dn-net/files/usr/lib/dn-net/uplink.sh /usr/lib/dn-net/
cp -a /etc/config /tmp/pristine/config; cp /etc/shadow /tmp/pristine/shadow

# A GL.iNet router's config, the parts the reader reads (GL 4.x on the GL-MT300N-V2 and the GL-X750).
gl_base() {
	rm -rf /etc/config /tmp/.uci /tmp/dn-handoff.tgz /tmp/dn-handoff; cp -a /tmp/pristine/config /etc/config
	cp /tmp/pristine/shadow /etc/shadow; sed -i "s|^root:[^:]*:|root:$HASH:|" /etc/shadow
	echo 4.3.28 > /etc/glversion
	echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDNtestkey owner' > /etc/dropbear/authorized_keys
	cat > /etc/config/network <<-'EOF'
	config interface 'lan'
		option device 'br-lan'
		option proto 'static'
		option ipaddr '192.168.8.1'
		option netmask '255.255.255.0'

	config interface 'wan'
		option device 'eth0'
		option proto 'dhcp'
	EOF
	cat > /etc/config/dhcp <<-'EOF'
	config host
		option name 'shelly1'
		option mac 'aa:bb:cc:00:00:01'
		option ip '192.168.8.21'
	EOF
}
# The GL-X750: 5 GHz radio0 listed first (and its AP first), 2.4 GHz radio1; the repeater on 5 GHz.
gl_x750_wifi() {
	cat > /etc/config/wireless <<-'EOF'
	config wifi-device 'radio0'
		option type 'mac80211'
		option hwmode '11a'
		option country 'US'

	config wifi-iface 'wifi5g'
		option device 'radio0'
		option network 'lan'
		option mode 'ap'
		option ssid 'Boat-5G'
		option encryption 'psk2'
		option key 'ap5-secret-9'

	config wifi-device 'radio1'
		option type 'mac80211'
		option band '2g'
		option country 'US'

	config wifi-iface 'wifi2g'
		option device 'radio1'
		option network 'lan'
		option mode 'ap'
		option ssid 'Boat'
		option encryption 'psk2'
		option key 'ap-secret-1'

	config wifi-iface 'guest2g'
		option device 'radio1'
		option network 'guest'
		option mode 'ap'
		option ssid 'Guest'

	config wifi-iface 'sta'
		option device 'radio0'
		option network 'wwan'
		option mode 'sta'
		option ssid 'Marina5'
		option encryption 'psk2'
		option key 'up-secret-2'
	EOF
}
# The GL-X750's modem as GL 4.x keeps it: named after its USB path, its dhcpv6 child listed first.
gl_x750_modem() {
	cat >> /etc/config/network <<-EOF

	config interface 'modem_1_1_2_6'
		option proto 'dhcpv6'
		option disabled '1'
		option device '@modem_1_1_2'

	config interface 'modem_1_1_2'
		option proto 'qmi'
		option device '/dev/cdc-wdm0'
		option apn 'broadband'
		option auth '${1:-PAP/CHAP}'
		option username 'lte-user'
		option password 'lte-secret-3'
		option pincode '${2-4321}'
		option ip_type 'IPV4V6'
		option metric '40'
		${3:+option disabled '$3'}
	EOF
}
# The renderer's starting point: a fresh DockNeighbor OS on a dual-band board with a modem.
dn_first_boot() {
	rm -rf /etc/config /tmp/.uci; cp -a /tmp/pristine/config /etc/config; cp /tmp/pristine/shadow /etc/shadow
	rm -f /etc/dn/site.json /etc/dn/handoff.result
	cat > /etc/config/network <<-'EOF'
	config interface 'lan'
		option device 'br-lan'
		option proto 'static'
		option ipaddr '192.168.1.1'
		option netmask '255.255.255.0'

	config interface 'wan'
		option device 'eth1'
		option proto 'dhcp'
	EOF
	cat > /etc/config/wireless <<-'EOF'
	config wifi-device 'radio0'
		option type 'mac80211'
		option band '5g'
		option disabled '1'

	config wifi-device 'radio1'
		option type 'mac80211'
		option band '2g'
		option disabled '1'
	EOF
	mkdir -p /lib/netifd/proto; [ -f /lib/netifd/proto/qmi.sh ] || echo '# test stand-in for uqmi' > /lib/netifd/proto/qmi.sh
}
# Run the reader; its stdout is what the app shows, so it must never carry a secret.
read_site() {
	sh "$READ" > /tmp/read.out 2>&1; rc=$?
	eq "reader exit status" "$rc" 0
	tar xzOf /tmp/dn-handoff.tgz etc/dn/site.json > /tmp/site.json 2>/dev/null || bad "no site.json in the tarball"
	for s in ap-secret-1 ap5-secret-9 up-secret-2 lte-secret-3 4321 lte-user '$5$'; do
		grep -qF -- "$s" /tmp/read.out && bad "the reader printed a secret ($s)"
	done
	pass "reader output: $(tr '\n' '|' < /tmp/read.out)"
}

echo "case R1: GL-X750 on GL 4.x: the 2.4 GHz AP, the 5 GHz repeater, the modem's APN, auth, PIN and IP type"
gl_base; gl_x750_wifi; gl_x750_modem
echo glinet,gl-x750 > /tmp/sysinfo/board_name
read_site
eq "source" "$(site @.source)" "glinet 4.3.28 glinet,gl-x750"
eq "ap is the 2.4 GHz one, though the 5 GHz one is listed first" "$(site @.ap.ssid)" Boat
eq "ap band" "$(site @.ap.band)" 2g
eq "country from the AP's radio" "$(site @.country)" US
eq "uplink band (from hwmode 11a)" "$(site @.uplink.band)" 5g
eq "lte apn" "$(site @.lte.apn)" broadband
eq "lte auth: GL's PAP/CHAP is qmi's both" "$(site @.lte.auth)" both
eq "lte username" "$(site @.lte.username)" lte-user
eq "lte password (in the tarball only)" "$(site @.lte.password)" lte-secret-3
eq "lte pincode (in the tarball only)" "$(site @.lte.pincode)" 4321
eq "lte pdptype from GL's ip_type" "$(site @.lte.pdptype)" ipv4v6
eq "lte enabled" "$(site @.lte.disabled)" ""
grep -q "^lte (network.modem_1_1_2) apn 'broadband' auth:both pin:set password:13B$" /tmp/read.out && pass "summary names the modem, not its secrets" || bad "summary: $(grep '^lte' /tmp/read.out)"
eq "enrollment files carried when present" "$(tar tzf /tmp/dn-handoff.tgz | grep -c brvg-hub-lite)" 0

echo "case R2: ... and the renderer brings that site up on DockNeighbor OS (dual-band, modem)"
cp /tmp/site.json /tmp/r1.json
dn_first_boot; cp /tmp/r1.json /etc/dn/site.json
sh "$APPLY"; eq "renderer exit status" "$?" 0
eq "AP on the 2.4 GHz radio" "$(uci get wireless.dn_ap.device)" radio1
eq "AP ssid/key" "$(uci get wireless.dn_ap.ssid)/$(uci get wireless.dn_ap.key)" Boat/ap-secret-1
eq "uplink on the 5 GHz radio" "$(uci get wireless.dn_uplink.device)" radio0
eq "lte proto/apn/auth" "$(uci get network.lte.proto)/$(uci get network.lte.apn)/$(uci get network.lte.auth)" qmi/broadband/both
eq "lte pin/password" "$(uci get network.lte.pincode)/$(uci get network.lte.password)" 4321/lte-secret-3
eq "lte pdptype" "$(uci get network.lte.pdptype)" ipv4v6
z=$(uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
eq "lte in the wan zone" "$(uci get firewall.$z.network | tr ' ' '\n' | grep -c '^lte$')" 1
eq "root password carried" "$(sed -n 's/^root:\([^:]*\):.*/\1/p' /etc/shadow)" "$HASH"
grep -q '^applied v1 lan=192.168.8.1 ap=Boat uplink=Marina5 (wan) reservations=1 password=carried lte=apn:broadband$' /etc/dn/handoff.result &&
	pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case R3: a router already running the hub-lite keeps its enrollment across the flash"
gl_base; gl_x750_wifi; gl_x750_modem
echo 'token=t' > /etc/brvg-hub-lite.conf; echo 'k' > /etc/brvg-hub-lite.keys
read_site
eq "hub-lite conf and keys in the tarball" "$(tar tzf /tmp/dn-handoff.tgz | grep -c -e 'etc/brvg-hub-lite.conf$' -e 'etc/brvg-hub-lite.keys$')" 2
rm -f /etc/brvg-hub-lite.conf /etc/brvg-hub-lite.keys

echo "case R4: a GL-MT300N-V2 (one radio, no modem) writes no lte, and no band it can't tell"
gl_base
cat > /etc/config/wireless <<-'EOF'
config wifi-device 'mt7628'
	option type 'mtk'
	option country 'US'

config wifi-iface 'wifi2g'
	option device 'mt7628'
	option network 'lan'
	option mode 'ap'
	option ssid 'Boat'
	option encryption 'psk2'
	option key 'ap-secret-1'
EOF
echo glinet,gl-mt300n-v2 > /tmp/sysinfo/board_name
read_site
eq "ap" "$(site @.ap.ssid)" Boat
eq "band from GL's interface name" "$(site @.ap.band)" 2g
eq "no lte object" "$(site @.lte)" ""
grep -q '^lte' /tmp/read.out && bad "summary mentions lte" || pass "no lte in the summary"

echo "case R5: a switched-off modem stays switched off; a plain NONE auth carries no credentials"
gl_base; gl_x750_wifi; gl_x750_modem NONE 4321 1
read_site
eq "lte disabled" "$(site @.lte.disabled)" true
eq "lte auth" "$(site @.lte.auth)" none
eq "no username/password for none" "$(site @.lte.username)$(site @.lte.password)" ""

echo "case R6: an auth or a PIN the renderer would refuse is left out, with a warning, so the rest still applies"
gl_base; gl_x750_wifi; gl_x750_modem MSCHAPV2 12
read_site
eq "no auth" "$(site @.lte.auth)" ""
eq "no pincode" "$(site @.lte.pincode)" ""
grep -q "WARNING: auth 'MSCHAPV2' not carried; a SIM PIN that is not 4 to 8 digits not carried;" /tmp/read.out &&
	pass "warned" || bad "no warning: $(grep '^lte' /tmp/read.out)"
cp /tmp/site.json /tmp/r6.json
dn_first_boot; cp /tmp/r6.json /etc/dn/site.json
sh "$APPLY"; eq "renderer applies it" "$?" 0
eq "lte apn" "$(uci get network.lte.apn)" broadband

echo "case R7: GL 4.x releases that keep the SIM's settings in /etc/config/glmodem (no modem interface)"
gl_base; gl_x750_wifi
cat > /etc/config/glmodem <<-'EOF'
config global 'global'
	option log_level '0'

config sim '8933150224012917678F'
	option proto 'qmi'
	option device '/dev/cdc-wdm0'
	option apn 'mifi'
	option ip_type 'IP'
	option auth 'NONE'
	option pincode '1111'
EOF
read_site
eq "lte apn from glmodem" "$(site @.lte.apn)" mifi
eq "lte pincode from glmodem" "$(site @.lte.pincode)" 1111
eq "lte pdptype IP is ipv4" "$(site @.lte.pdptype)" ipv4
grep -q '1111' /tmp/read.out && bad "the reader printed the PIN" || pass "PIN not printed"
rm -f /etc/config/glmodem

echo "case R8: the PIN lives only in glmodem (per SIM): carried when exactly one SIM has one"
gl_base; gl_x750_wifi; gl_x750_modem NONE ""
cat > /etc/config/glmodem <<-'EOF'
config sim '8933150224012917678F'
	option pincode '2468'
EOF
read_site
eq "pin from the one SIM section" "$(site @.lte.pincode)" 2468
cat >> /etc/config/glmodem <<-'EOF'

config sim '8933150224012917679F'
	option pincode '1357'
EOF
read_site
eq "two SIMs with PINs: neither guessed" "$(site @.lte.pincode)" ""
rm -f /etc/config/glmodem

[ "$fails" -eq 0 ] || { echo "read.test: $fails failure(s)"; exit 1; }
echo "read.test: all cases pass"
