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

[ "$fails" -eq 0 ] || { echo "apply.test: $fails failure(s)"; exit 1; }
echo "apply.test: all cases pass"
