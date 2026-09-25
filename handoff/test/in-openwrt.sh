#!/bin/sh
# Inside an OpenWrt rootfs container (handoff/test/apply.test.sh). Each case starts from a clean config.
APPLY=/t/feed/dn-handoff/files/usr/libexec/dn-handoff/apply
SITE=/etc/dn/site.json
HASH='$5$abcdefgh$0123456789abcdefghijklmnopqrstuvwxyzABCDEFG'
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }

mkdir -p /etc/dn /tmp/pristine /usr/lib/dn-net
# dn-handoff sources dn-net's uplink.sh (the one role -> firewall rule).
cp /t/feed/dn-net/files/usr/lib/dn-net/uplink.sh /usr/lib/dn-net/
cp -a /etc/config /tmp/pristine/config; cp /etc/shadow /tmp/pristine/shadow
reset() {
	rm -rf /etc/config /tmp/.uci; cp -a /tmp/pristine/config /etc/config; cp /tmp/pristine/shadow /etc/shadow
	rm -f "$SITE" /etc/dn/handoff.result /tmp/dn-handoff.shadow
	# What OpenWrt's config_generate writes at first boot, before uci-defaults run (a container never boots).
	cat > /etc/config/network <<-'EOF'
	config interface 'loopback'
		option device 'lo'
		option proto 'static'
		option ipaddr '127.0.0.1'
		option netmask '255.0.0.0'

	config interface 'lan'
		option device 'br-lan'
		option proto 'static'
		option ipaddr '192.168.1.1'
		option netmask '255.255.255.0'

	config interface 'wan'
		option device 'eth0.2'
		option proto 'dhcp'
	EOF
	# A container has no Wi-Fi hardware: stand in for what OpenWrt's first-boot detect writes.
	cat > /etc/config/wireless <<-'EOF'
	config wifi-device 'radio0'
		option type 'mac80211'
		option band '2g'
		option disabled '1'

	config wifi-iface 'default_radio0'
		option device 'radio0'
		option network 'lan'
		option mode 'ap'
		option ssid 'OpenWrt'
		option encryption 'none'
	EOF
}
wan_zone() { uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p"; }

echo "case 1: a full GL.iNet site"
reset
cat > "$SITE" <<EOF
{ "v": 1, "source": "test", "lan": { "ip": "192.168.8.1", "mask": "255.255.255.0" }, "country": "US",
  "ap": { "ssid": "Boat AP", "enc": "psk2", "key": "ap-secret-1" },
  "uplink": { "type": "wifi", "ssid": "Boatnet", "enc": "psk-mixed", "key": "up-secret-2", "role": "lan" },
  "reservations": [ { "name": "shelly1", "mac": "aa:bb:cc:00:00:01", "ip": "192.168.8.21" },
                    { "name": "linktap", "mac": "aa:bb:cc:00:00:02", "ip": "192.168.8.22" } ],
  "rootHash": "$HASH" }
EOF
sh "$APPLY"; eq "exit status" "$?" 0
eq "lan ip" "$(uci get network.lan.ipaddr)" 192.168.8.1
eq "radio enabled" "$(uci get wireless.radio0.disabled)" 0
eq "country" "$(uci get wireless.radio0.country)" US
eq "ap ssid" "$(uci get wireless.dn_ap.ssid)" "Boat AP"
eq "ap key" "$(uci get wireless.dn_ap.key)" ap-secret-1
eq "default open AP removed" "$(uci -q get wireless.default_radio0 || echo gone)" gone
eq "uplink ssid" "$(uci get wireless.dn_uplink.ssid)" Boatnet
eq "uplink mode" "$(uci get wireless.dn_uplink.mode)" sta
eq "uplink enc" "$(uci get wireless.dn_uplink.encryption)" psk-mixed
eq "wwan proto" "$(uci get network.wwan.proto)" dhcp
z=$(wan_zone); eq "wwan NOT in the wan zone (it drops input)" "$(uci get firewall.$z.network | tr ' ' '\n' | grep -c '^wwan$')" 0
eq "wwan in the uplink zone once" "$(uci get firewall.dn_uplink.network | tr ' ' '\n' | grep -c '^wwan$')" 1
eq "uplink zone accepts input like LAN (the boat network reaches 8722/8181/22)" "$(uci get firewall.dn_uplink.input)" ACCEPT
eq "uplink zone still NATs the router's own AP clients" "$(uci get firewall.dn_uplink.masq)" 1
eq "lan forwards to the uplink" "$(uci get firewall.dn_uplink_fwd.src)->$(uci get firewall.dn_uplink_fwd.dest)" "lan->uplink"
eq "reservations" "$(uci show dhcp | grep -c '=host$')" 2
eq "reservation ip" "$(uci show dhcp | grep -F "ip='192.168.8.22'" | wc -l | tr -d ' ')" 1
eq "root hash" "$(sed -n 's/^root:\([^:]*\):.*/\1/p' /etc/shadow)" "$HASH"
eq "site file removed" "$([ -f "$SITE" ] && echo present || echo removed)" removed
eq "committed (nothing left staged)" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q 'secret' /etc/dn/handoff.result && bad "result file leaks a key" || pass "result file has no keys"
grep -q '^applied v1 .*uplink=Boatnet (lan) reservations=2 password=carried' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 2: no site file is a no-op"
reset
sh "$APPLY"; eq "exit status" "$?" 0
eq "lan unchanged" "$(uci get network.lan.ipaddr)" 192.168.1.1

echo "case 3: minimal site leaves Wi-Fi alone"
reset
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "lan ip" "$(uci get network.lan.ipaddr)" 10.9.8.1
eq "radio untouched" "$(uci get wireless.radio0.disabled)" 1
eq "default AP untouched" "$(uci get wireless.default_radio0.ssid)" OpenWrt

echo "case 4: an unknown version fails, keeps the site file, changes nothing"
reset
echo '{ "v": 2, "lan": { "ip": "10.9.8.1" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "site file kept for retry" "$([ -f "$SITE" ] && echo present || echo removed)" present
eq "lan unchanged" "$(uci get network.lan.ipaddr)" 192.168.1.1

echo "case 5: a late failure reverts what it staged (so no later commit can apply half a site)"
reset
cat > "$SITE" <<'EOF'
{ "v": 1, "lan": { "ip": "10.9.8.1" }, "ap": { "ssid": "X", "key": "k" },
  "reservations": [ { "name": "a", "mac": "aa:bb:cc:00:00:09", "ip": "10.9.8.9" } ], "rootHash": "bad|hash" }
EOF
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
uci commit
eq "lan unchanged after a later commit" "$(uci get network.lan.ipaddr)" 192.168.1.1
eq "no reservation" "$(uci show dhcp | grep -c '=host$')" 0
eq "shadow unchanged" "$(cmp -s /etc/shadow /tmp/pristine/shadow && echo same || echo changed)" same
grep -q '^failed: admin password hash' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 5b: a uci write that fails is a failure, never reported as applied"
reset
uci delete network.lan; uci commit network
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "site file kept for retry" "$([ -f "$SITE" ] && echo present || echo removed)" present
grep -q '^failed: uci set network.lan.ipaddr$' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 6: a retry after success does not duplicate the uplink zone or its entry"
reset
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "M", "key": "k1234567", "role": "lan" } }' > "$SITE"
sh "$APPLY" >/dev/null
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "M", "key": "k1234567", "role": "lan" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "wwan in the uplink zone once" "$(uci get firewall.dn_uplink.network | tr ' ' '\n' | grep -c '^wwan$')" 1
eq "one uplink zone" "$(uci show firewall | grep -c "name='uplink'")" 1
eq "one lan->uplink forwarding" "$(uci show firewall | grep -c "dest='uplink'")" 1

in_zone() { uci -q get "firewall.$1.network" | tr ' ' '\n' | grep -c '^wwan$'; }

echo "case 7: an uplink with NO role is a wan uplink (restricted), the safe default"
reset
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "Marina", "key": "k1234567" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "wwan in the wan zone (drops input)" "$(in_zone "$(wan_zone)")" 1
eq "no open uplink zone" "$(uci -q get firewall.dn_uplink.network | wc -w | tr -d ' ')" 0
grep -q 'uplink=Marina (wan)' /etc/dn/handoff.result && pass "result says wan" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 8: role wan, explicitly (a marina's public Wi-Fi)"
reset
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "Marina", "key": "k1234567", "role": "wan" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "wwan in the wan zone" "$(in_zone "$(wan_zone)")" 1
eq "not in an open zone" "$(in_zone dn_uplink)" 0

echo "case 9: re-applying with a changed role moves wwan, never leaves it in both zones"
reset
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "B", "key": "k1234567", "role": "lan" } }' > "$SITE"; sh "$APPLY" >/dev/null
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "B", "key": "k1234567", "role": "wan" } }' > "$SITE"; sh "$APPLY"
eq "lan -> wan: now in wan" "$(in_zone "$(wan_zone)")" 1
eq "lan -> wan: no longer open" "$(in_zone dn_uplink)" 0
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "B", "key": "k1234567", "role": "lan" } }' > "$SITE"; sh "$APPLY"
eq "wan -> lan: now open" "$(in_zone dn_uplink)" 1
eq "wan -> lan: no longer in wan" "$(in_zone "$(wan_zone)")" 0

echo "case 10: an unknown role fails and changes nothing"
reset
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" }, "uplink": { "type": "wifi", "ssid": "X", "key": "k1234567", "role": "dmz" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q "^failed: unknown uplink role 'dmz'" /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

# ---- dual-band boards (GL-X750: radio0 is the 5 GHz ath10k, radio1 the 2.4 GHz SoC radio) ----
dual_band() {
	cat > /etc/config/wireless <<-'EOF'
	config wifi-device 'radio0'
		option type 'mac80211'
		option band '5g'
		option disabled '1'

	config wifi-iface 'default_radio0'
		option device 'radio0'
		option network 'lan'
		option mode 'ap'
		option ssid 'OpenWrt'
		option encryption 'none'

	config wifi-device 'radio1'
		option type 'mac80211'
		option band '2g'
		option disabled '1'

	config wifi-iface 'default_radio1'
		option device 'radio1'
		option network 'lan'
		option mode 'ap'
		option ssid 'OpenWrt'
		option encryption 'none'
	EOF
}

echo "case 11: dual-band board: the AP goes on the 2.4 GHz radio (the default band), the uplink on its own band"
reset; dual_band
echo '{ "v": 1, "country": "US", "ap": { "ssid": "Boat AP", "key": "ap-secret-1" }, "uplink": { "type": "wifi", "ssid": "Marina5", "key": "k1234567", "band": "5g" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "AP on the 2.4 GHz radio" "$(uci get wireless.dn_ap.device)" radio1
eq "uplink on the 5 GHz radio" "$(uci get wireless.dn_uplink.device)" radio0
eq "2.4 GHz radio enabled" "$(uci get wireless.radio1.disabled)" 0
eq "5 GHz radio enabled (it carries the uplink)" "$(uci get wireless.radio0.disabled)" 0
eq "country on both" "$(uci get wireless.radio0.country)/$(uci get wireless.radio1.country)" US/US
eq "the 2.4 GHz default open AP replaced" "$(uci -q get wireless.default_radio1 || echo gone)" gone
eq "the 5 GHz default AP left as it was" "$(uci get wireless.default_radio0.ssid)" OpenWrt

echo "case 12: dual-band: a 2g AP and a 2g uplink share the 2.4 GHz radio; the 5 GHz radio stays off"
reset; dual_band
echo '{ "v": 1, "ap": { "ssid": "A", "key": "ap-secret-1", "band": "2g" }, "uplink": { "type": "wifi", "ssid": "B", "key": "k1234567", "band": "2g" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "AP radio" "$(uci get wireless.dn_ap.device)" radio1
eq "uplink radio" "$(uci get wireless.dn_uplink.device)" radio1
eq "5 GHz radio untouched" "$(uci get wireless.radio0.disabled)" 1

echo "case 13: a single-band board takes a 5g site on its only radio"
reset
echo '{ "v": 1, "ap": { "ssid": "A", "key": "ap-secret-1", "band": "5g" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "AP radio" "$(uci get wireless.dn_ap.device)" radio0

echo "case 14: an unknown band fails and changes nothing"
reset; dual_band
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" }, "ap": { "ssid": "A", "key": "ap-secret-1", "band": "3g" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q "^failed: unknown Wi-Fi band '3g'" /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

# ---- LTE (a board with a QMI modem). The image's uqmi installs netifd's proto qmi; stand in for it. ----
QMI=/lib/netifd/proto/qmi.sh
modem() { mkdir -p /lib/netifd/proto; [ -f "$QMI" ] || { echo '# test stand-in for uqmi' > "$QMI"; touch /tmp/qmi.stub; }; }
no_modem() { [ -f /tmp/qmi.stub ] && rm -f "$QMI" /tmp/qmi.stub; [ ! -f "$QMI" ]; }
in_wan() { uci get "firewall.$(wan_zone).network" | tr ' ' '\n' | grep -c "^$1\$"; }
LTE_SITE='{ "v": 1, "lan": { "ip": "192.168.8.1" }, "lte": { "apn": "broadband", "pincode": "4321", "auth": "both", "username": "lte-user", "password": "lte-secret-3", "pdptype": "ipv4" } }'

echo "case 15: the modem's settings become a qmi interface in the wan zone (restricted, like any internet uplink)"
reset; modem
echo "$LTE_SITE" > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "proto" "$(uci get network.lte.proto)" qmi
eq "control device" "$(uci get network.lte.device)" /dev/cdc-wdm0
eq "apn" "$(uci get network.lte.apn)" broadband
eq "pincode" "$(uci get network.lte.pincode)" 4321
eq "auth" "$(uci get network.lte.auth)" both
eq "username" "$(uci get network.lte.username)" lte-user
eq "password" "$(uci get network.lte.password)" lte-secret-3
eq "pdptype (qmi.sh calls IPv4 'ip')" "$(uci get network.lte.pdptype)" ip
eq "metric: behind a wired (0) and a Wi-Fi (20) uplink" "$(uci get network.lte.metric)" 30
eq "enabled" "$(uci -q get network.lte.disabled || echo unset)" unset
eq "lte in the wan zone once (drops input)" "$(in_wan lte)" 1
eq "lte not in an open zone" "$(uci -q get firewall.dn_uplink.network | tr ' ' '\n' | grep -c '^lte$')" 0
eq "committed (nothing left staged)" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q -e 'secret' -e '4321' -e 'lte-user' /etc/dn/handoff.result && bad "result file leaks an LTE secret" || pass "result file has no PIN, username or password"
grep -q ' lte=apn:broadband$' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 16: a retry does not duplicate lte in the wan zone or keep stale secrets; LTE and a lan-role Wi-Fi uplink coexist"
reset; modem
echo "$LTE_SITE" > "$SITE"; sh "$APPLY" >/dev/null
echo '{ "v": 1, "uplink": { "type": "wifi", "ssid": "Boatnet", "key": "k1234567", "role": "lan" }, "lte": { "apn": "broadband" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "lte in the wan zone once" "$(in_wan lte)" 1
eq "wwan in the open uplink zone" "$(uci get firewall.dn_uplink.network | tr ' ' '\n' | grep -c '^wwan$')" 1
eq "wwan not in wan" "$(in_wan wwan)" 0
eq "no stale auth, password or PIN from the first apply" "$(uci -q get network.lte.auth || echo unset)/$(uci -q get network.lte.password || echo unset)/$(uci -q get network.lte.pincode || echo unset)" unset/unset/unset

echo "case 17: an APN-less modem (the SIM's default) that the owner switched off"
reset; modem
echo '{ "v": 1, "lte": { "apn": "", "disabled": true } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "no apn: the modem's default" "$(uci -q get network.lte.apn || echo unset)" unset
eq "kept switched off" "$(uci get network.lte.disabled)" 1
eq "no auth for none" "$(uci -q get network.lte.auth || echo unset)" unset
grep -q ' lte=apn:default,disabled$' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 18: an unknown LTE auth fails, keeps the site file, changes nothing"
reset; modem
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" }, "lte": { "apn": "x", "auth": "mschap", "password": "lte-secret-3" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
eq "site file kept for retry" "$([ -f "$SITE" ] && echo present || echo removed)" present
eq "no lte interface" "$(uci -q get network.lte || echo none)" none
grep -q "^failed: unknown lte auth 'mschap'$" /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 19: a malformed SIM PIN fails without ever printing it"
reset; modem
echo '{ "v": 1, "lan": { "ip": "10.9.8.1" }, "lte": { "apn": "x", "pincode": "12a45" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q '12a45' /etc/dn/handoff.result && bad "result leaks the PIN" || pass "result: $(cat /etc/dn/handoff.result)"

echo "case 20: an unknown pdptype fails"
reset; modem
echo '{ "v": 1, "lte": { "apn": "x", "pdptype": "ppp" } }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
grep -q "^failed: unknown lte pdptype 'ppp'$" /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 21: a late failure after the LTE is staged reverts it too"
reset; modem
echo '{ "v": 1, "lte": { "apn": "broadband", "pincode": "4321" }, "rootHash": "bad|hash" }' > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
uci commit
eq "no lte interface after a later commit" "$(uci -q get network.lte || echo none)" none
eq "wan zone unchanged" "$(in_wan lte)" 0

echo "case 22: no wan zone to put the modem in is a failure, never an unfirewalled modem"
reset; modem
uci set "firewall.$(wan_zone).name=wan-renamed"; uci commit firewall
echo "$LTE_SITE" > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 1
eq "nothing staged" "$(uci changes | wc -l | tr -d ' ')" 0
grep -q '^failed: no wan firewall zone$' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

echo "case 23: LTE settings on a board without modem support: the rest of the site still applies"
reset; no_modem || bad "the test rootfs ships a real proto qmi"
echo "$LTE_SITE" > "$SITE"
sh "$APPLY"; eq "exit status" "$?" 0
eq "lan applied" "$(uci get network.lan.ipaddr)" 192.168.8.1
eq "no lte interface" "$(uci -q get network.lte || echo none)" none
grep -q ' lte=skipped (no modem support in this image)$' /etc/dn/handoff.result && pass "result: $(cat /etc/dn/handoff.result)" || bad "result: $(cat /etc/dn/handoff.result)"

[ "$fails" -eq 0 ] || { echo "apply.test: $fails failure(s)"; exit 1; }
echo "apply.test: all cases pass"
