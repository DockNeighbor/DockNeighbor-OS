#!/bin/sh
# Inside an OpenWrt rootfs container (feed/dn-net/test/net.test.sh): the real dn-net against real uci. There's no
# Wi-Fi hardware or netifd in a container, so iwinfo, ifstatus and `ip route/neigh` are stubs fed from fixtures
# in the shapes the router prints; everything else is real. DN_NET_NO_APPLY=1: nothing is reloaded.
NET=/t/feed/dn-net/files/usr/sbin/dn-net
mkdir -p /usr/lib/dn-net /tmp/stub /tmp/fx; cp /t/feed/dn-net/files/usr/lib/dn-net/uplink.sh /usr/lib/dn-net/
cp /t/feed/dn-net/files/etc/config/dn-net /etc/config/dn-net
export DN_NET_NO_APPLY=1 DN_NET_LEASES=/tmp/fx/leases PATH=/tmp/stub:$PATH
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
# eq LABEL ACTUAL EXPECTED, always in that order.
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }
j() { jsonfilter -s "$1" -e "$2"; }
net() { _v=$1; shift; printf '%s' "${1:-}" | sh "$NET" "$_v" 2>/tmp/err; }
staged() { uci changes | wc -l | tr -d ' '; }

# --- stubs --------------------------------------------------------------------------------------
cat > /tmp/stub/iwinfo <<'EOF'
#!/bin/sh
case "$2" in
  scan) cat /tmp/fx/scan ;;
  # 24.10's real freqlist format (bench MT300N-V2, 2026-09-25).
  freqlist) printf '* 2.412 GHz (Band: 2.4 GHz, Channel 1) [NO_HT40-, NO_80MHZ, NO_160MHZ]\n  2.437 GHz (Band: 2.4 GHz, Channel 6) [NO_HT40-]\n  2.462 GHz (Band: 2.4 GHz, Channel 11) [NO_HT40+]\n' ;;
  assoclist) cat /tmp/fx/assoc 2>/dev/null ;;
  info) printf 'phy0-sta0 ESSID: "Boatnet"\n          Mode: Client  Channel: 6 (2.437 GHz)  HT Mode: HT20\n          Signal: -48 dBm  Noise: -95 dBm\n' ;;
esac
EOF
cat > /tmp/stub/ifstatus <<'EOF'
#!/bin/sh
[ -f "/tmp/fx/if.$1" ] && cat "/tmp/fx/if.$1" || echo '{"up":false}'
EOF
cat > /tmp/stub/ip <<'EOF'
#!/bin/sh
case "$*" in
  "-4 route show default") cat /tmp/fx/route 2>/dev/null ;;
  "-4 neigh show dev br-lan") cat /tmp/fx/neigh 2>/dev/null ;;
  *) exec /sbin/ip "$@" ;;
esac
EOF
chmod 755 /tmp/stub/*

# --- a router's config, as first boot writes it -------------------------------------------------
cat > /etc/config/network <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'
config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '192.168.8.1'
	option netmask '255.255.255.0'
config interface 'wan'
	option device 'eth0.2'
	option proto 'dhcp'
EOF
cat > /etc/config/wireless <<'EOF'
config wifi-device 'radio0'
	option type 'mac80211'
	option band '2g'
	option channel 'auto'
	option country 'US'
config wifi-iface 'dn_ap'
	option device 'radio0'
	option network 'lan'
	option mode 'ap'
	option ssid 'Boat AP'
	option encryption 'psk2'
	option key 'ap-secret-1'
EOF
uci set dhcp.lan.start=100; uci set dhcp.lan.limit=150; uci commit dhcp
cat > /tmp/fx/scan <<'EOF'
Cell 01 - Address: 24:29:34:C3:F9:73
          ESSID: "Boatnet"
          Mode: Master  Channel: 6
          Signal: -48 dBm  Quality: 62/70
          Encryption: mixed WPA2/WPA3 PSK/SAE (CCMP)

Cell 02 - Address: 0A:0B:0C:0D:0E:0F
          ESSID: "Marina Guest"
          Mode: Master  Channel: 11
          Signal: -71 dBm  Quality: 39/70
          Encryption: none

Cell 03 - Address: 11:22:33:44:55:66
          ESSID: "Dock 5G"
          Mode: Master  Channel: 149
          Signal: -80 dBm  Quality: 30/70
          Encryption: WPA2 PSK (CCMP)
EOF

echo "lan"
r=$(net lan-get)
eq "lan-get: ip, mask, and the DHCP range as addresses" "$(j "$r" '@.ip') $(j "$r" '@.netmask') $(j "$r" '@.dhcpStart') $(j "$r" '@.dhcpEnd')" \
  "192.168.8.1 255.255.255.0 192.168.8.100 192.168.8.249"
r=$(net lan-set '{"ip":"10.20.0.1","netmask":"255.255.255.0","dhcpStart":"10.20.0.50","dhcpEnd":"10.20.0.99"}'); eq "lan-set: exit" "$?" 0
eq "lan-set: committed" "$(uci get network.lan.ipaddr) $(uci get dhcp.lan.start) $(uci get dhcp.lan.limit)" "10.20.0.1 50 50"
eq "lan-set: answers the new config" "$(j "$r" '@.dhcpEnd')" "10.20.0.99"
net lan-set '{"ip":"10.30.0.1","netmask":"255.255.255.0","dhcpStart":"10.99.0.5","dhcpEnd":"10.99.0.9"}' >/dev/null; eq "lan-set: a range outside the LAN is refused" "$?" 2
eq "lan-set: ...and nothing is staged" "$(staged)" 0
eq "lan-set: ...and the LAN is unchanged" "$(uci get network.lan.ipaddr)" 10.20.0.1
net lan-set '{"ip":"10.20.0.300"}' >/dev/null; eq "lan-set: a bad address is refused" "$?" 2
net lan-set 'not json' >/dev/null; eq "lan-set: a body that isn't JSON is refused" "$?" 2

echo "wifi"
uci set wireless.dn_uplink=wifi-iface; uci set wireless.dn_uplink.device=radio0; uci set wireless.dn_uplink.mode=sta
uci set wireless.dn_uplink.ssid=Boatnet; uci commit wireless
r=$(net wifi-get)
eq "wifi-get: one radio, band 2G, auto channel as 0" "$(j "$r" '@.radios[0].device') $(j "$r" '@.radios[0].band') $(j "$r" '@.radios[0].channel')" "radio0 2G 0"
eq "wifi-get: channels from the radio" "$(j "$r" '@.radios[0].channels[*]' | tr '\n' ' ' | sed 's/ $//')" "1 6 11"
eq "wifi-get: lists the access point" "$(j "$r" '@.radios[0].networks[0].iface') $(j "$r" '@.radios[0].networks[0].ssid') $(j "$r" '@.radios[0].networks[0].enabled')" "dn_ap Boat AP true"
eq "wifi-get: never lists the uplink (a client, not an AP)" "$(j "$r" '@.radios[0].networks[*].iface' | wc -l | tr -d ' ')" "1"
eq "wifi-get: the key is there for a caller who may configure" "$(j "$r" '@.radios[0].networks[0].key')" "ap-secret-1"
eq "wifi-get: DN_NET_REDACT leaves every key out" "$(DN_NET_REDACT=1 net wifi-get | grep -c '"key"')" "0"
r=$(net wifi-set '{"iface":"dn_ap","ssid":"Seas the Day","key":"new-secret-22"}'); eq "wifi-set: exit" "$?" 0
eq "wifi-set: committed" "$(uci get wireless.dn_ap.ssid) $(uci get wireless.dn_ap.key)" "Seas the Day new-secret-22"
net wifi-set '{"iface":"dn_ap","encryption":"sae","key":"short"}' >/dev/null; eq "wifi-set: a 5-character key is refused" "$?" 2
eq "wifi-set: ...and the encryption staged before it is reverted" "$(staged) psk2" "0 $(uci get wireless.dn_ap.encryption)"
net wifi-set '{"iface":"dn_uplink","ssid":"x"}' >/dev/null; eq "wifi-set: the uplink can't be changed as an AP" "$?" 2
r=$(net wifi-set '{"device":"radio0","channel":6}'); eq "wifi-set: channel on the radio" "$(uci get wireless.radio0.channel)" 6
net wifi-set '{"device":"radio0","channel":0}' >/dev/null; eq "wifi-set: channel 0 is auto" "$(uci get wireless.radio0.channel)" auto

echo "uplink"
r=$(net uplink-scan)
eq "scan: three networks" "$(j "$r" '@.networks[*].ssid' | wc -l | tr -d ' ')" "3"
eq "scan: ssid, bssid, band, channel, signal" "$(j "$r" '@.networks[0].ssid') $(j "$r" '@.networks[0].bssid') $(j "$r" '@.networks[0].band') $(j "$r" '@.networks[0].channel') $(j "$r" '@.networks[0].signal')" \
  "Boatnet 24:29:34:C3:F9:73 2g 6 -48"
eq "scan: open vs secured" "$(j "$r" '@.networks[*].secured' | tr '\n' ' ' | sed 's/ $//')" "true false true"
eq "scan: channel 149 is 5g" "$(j "$r" '@.networks[2].band')" "5g"
eq "scan: nothing saved yet" "$(j "$r" '@.networks[0].saved')" "false"

wan_zone() { uci show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p"; }
in_zone() { uci -q get "firewall.$1.network" | tr ' ' '\n' | grep -c '^wwan$'; }
r=$(net uplink-join '{"ssid":"Boatnet","key":"boat-key-1234","role":"lan"}'); eq "join lan: exit" "$?" 0
eq "join lan: answers connecting" "$(j "$r" '@.state') $(j "$r" '@.role')" "connecting lan"
eq "join lan: a client iface on the uplink" "$(uci get wireless.dn_uplink.mode) $(uci get wireless.dn_uplink.ssid) $(uci get wireless.dn_uplink.network)" "sta Boatnet wwan"
eq "join lan: encryption from what the router sees (mixed WPA2/WPA3)" "$(uci get wireless.dn_uplink.encryption)" "sae-mixed"
eq "join lan: the open uplink zone" "$(in_zone dn_uplink) $(in_zone "$(wan_zone)")" "1 0"
eq "join lan: remembered, with its role" "$(j "$(net uplink-saved)" '@.networks[0].ssid') $(j "$(net uplink-saved)" '@.networks[0].role')" "Boatnet lan"
eq "join lan: scan now marks it saved" "$(j "$(net uplink-scan)" '@.networks[0].saved')" "true"
r=$(net uplink-join '{"ssid":"Marina Guest"}'); eq "join, no role: exit" "$?" 0
eq "join, no role: wan (restricted) is the default" "$(in_zone dn_uplink) $(in_zone "$(wan_zone)")" "0 1"
eq "join, open network: encryption none, no key" "$(uci get wireless.dn_uplink.encryption) $(uci -q get wireless.dn_uplink.key)" "none "
eq "join: still one saved entry per network" "$(j "$(net uplink-saved)" '@.networks[*].ssid' | wc -l | tr -d ' ')" "2"
net uplink-join '{"ssid":"Dock 5G"}' >/dev/null; eq "join: a secured network without a key is refused" "$?" 2
net uplink-join '{"ssid":"Boatnet","key":"boat-key-1234","role":"dmz"}' >/dev/null; eq "join: an unknown role is refused" "$?" 2
eq "join: refusals stage nothing" "$(staged)" 0
eq "join: ...and the uplink is unchanged" "$(uci get wireless.dn_uplink.ssid)" "Marina Guest"

r=$(net uplink-get); eq "uplink-get: joined, no address yet: connecting" "$(j "$r" '@.state') $(j "$r" '@.ssid') $(j "$r" '@.role')" "connecting Marina Guest wan"
echo '{"up":true,"ipv4-address":[{"address":"192.168.86.176","mask":24}],"route":[{"target":"0.0.0.0","mask":0,"nexthop":"192.168.86.1"}]}' > /tmp/fx/if.wwan
r=$(net uplink-get); eq "uplink-get: connected, with address, gateway, channel, signal" "$(j "$r" '@.state') $(j "$r" '@.ip') $(j "$r" '@.gateway') $(j "$r" '@.channel') $(j "$r" '@.signal') $(j "$r" '@.band')" \
  "connected 192.168.86.176 192.168.86.1 6 -48 2g"
echo 'default via 192.168.86.1 dev phy0-sta0 proto static src 192.168.86.176 metric 20' > /tmp/fx/route
r=$(net wan); eq "wan: the default route is the Wi-Fi uplink" "$(j "$r" '@.wan') $(j "$r" '@.up') $(j "$r" '@.ip')" "repeater true 192.168.86.176"
: > /tmp/fx/route; eq "wan: no default route is none, down" "$(j "$(net wan)" '@.wan') $(j "$(net wan)" '@.up')" "none false"
r=$(net uplink-disconnect); eq "disconnect: idle" "$(j "$r" '@.state') $(uci get wireless.dn_uplink.disabled)" "idle 1"
eq "uplink-get: after disconnect, idle" "$(j "$(net uplink-get)" '@.state')" "idle"
r=$(net uplink-forget '{"ssid":"Marina Guest"}'); eq "forget: gone from saved" "$(j "$r" '@.networks[*].ssid' | tr '\n' ' ' | sed 's/ $//')" "Boatnet"
net uplink-forget '{"ssid":"Nope"}' >/dev/null; eq "forget: an unknown network is refused" "$?" 2

echo "clients"
printf '1790300000 aa:bb:cc:00:00:01 192.168.8.21 shelly1 01:aa:bb:cc:00:00:01\n1790300000 aa:bb:cc:00:00:02 192.168.8.22 * *\n' > /tmp/fx/leases
printf 'Station AA:BB:CC:00:00:01 (on phy0-ap0)\n' > /tmp/fx/assoc
printf 'AA:BB:CC:00:00:01  -52 dBm / -95 dBm (SNR 43)  10 ms ago\n' > /tmp/fx/assoc
# `ip neigh show dev br-lan` prints no dev field once dev is named.
printf '192.168.8.22 lladdr aa:bb:cc:00:00:02 REACHABLE\n192.168.8.30 lladdr aa:bb:cc:00:00:03 STALE\n' > /tmp/fx/neigh
r=$(net clients)
eq "clients: every source, once each" "$(j "$r" '@.clients[*].mac' | tr '\n' ' ' | sed 's/ $//')" "aa:bb:cc:00:00:01 aa:bb:cc:00:00:02 aa:bb:cc:00:00:03"
eq "clients: a Wi-Fi client, by name" "$(j "$r" '@.clients[0].name') $(j "$r" '@.clients[0].ip') $(j "$r" '@.clients[0].link') $(j "$r" '@.clients[0].online')" "shelly1 192.168.8.21 2g true"
eq "clients: a wired client, reachable" "$(j "$r" '@.clients[1].link') $(j "$r" '@.clients[1].online')" "wired true"
eq "clients: a stale neighbour is offline" "$(j "$r" '@.clients[2].online')" "false"
r=$(net client-block '{"mac":"AA:BB:CC:00:00:02","blocked":true}'); eq "block: exit" "$?" 0
eq "block: the client shows blocked" "$(j "$r" '@.clients[1].blocked')" "true"
eq "block: denied internet, still on the LAN" "$(uci get firewall.dn_block_aabbcc000002.src) $(uci get firewall.dn_block_aabbcc000002.src_mac) $(uci get firewall.dn_block_aabbcc000002.dest) $(uci get firewall.dn_block_aabbcc000002.target)" \
  "lan aa:bb:cc:00:00:02 * REJECT"
r=$(net client-block '{"mac":"aa:bb:cc:00:00:02","blocked":false}'); eq "unblock: rule gone" "$(uci -q get firewall.dn_block_aabbcc000002 || echo none) $(j "$r" '@.clients[1].blocked')" "none false"
net client-block '{"mac":"nope"}' >/dev/null; eq "block: a bad MAC is refused" "$?" 2

echo "reservations"
r=$(net reservation-add '{"mac":"AA:BB:CC:00:00:01","ip":"192.168.8.21","name":"shelly1"}'); eq "add: exit" "$?" 0
eq "add: listed, MAC lower-cased" "$(j "$r" '@.reservations[0].mac') $(j "$r" '@.reservations[0].ip') $(j "$r" '@.reservations[0].name')" "aa:bb:cc:00:00:01 192.168.8.21 shelly1"
r=$(net reservation-add '{"mac":"aa:bb:cc:00:00:01","ip":"192.168.8.25"}'); eq "add: the same MAC again replaces, never duplicates" "$(j "$r" '@.reservations[*].mac' | wc -l | tr -d ' ') $(j "$r" '@.reservations[0].ip')" "1 192.168.8.25"
net reservation-add '{"mac":"aa:bb:cc:00:00:09","ip":"192.168.8.25"}' >/dev/null; eq "add: an address reserved for another MAC is refused" "$?" 2
eq "add: ...nothing staged" "$(staged)" 0
r=$(net reservation-remove '{"mac":"aa:bb:cc:00:00:01"}'); eq "remove: gone" "$(j "$r" '@.reservations[*].mac' | wc -l | tr -d ' ')" "0"
net reservation-remove '{"mac":"aa:bb:cc:00:00:01"}' >/dev/null; eq "remove: an unknown MAC is refused" "$?" 2

echo "mode (router / bridge)"
# The MT300N-V2's real layout: br-lan holds eth0.1, the WAN is eth0.2.
cat > /etc/config/network <<'EOF'
config interface 'loopback'
	option device 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'
config device
	option name 'br-lan'
	option type 'bridge'
	list ports 'eth0.1'
config interface 'lan'
	option device 'br-lan'
	option proto 'static'
	option ipaddr '192.168.8.1'
	option netmask '255.255.255.0'
	option ip6assign '60'
config interface 'wan'
	option device 'eth0.2'
	option proto 'dhcp'
config interface 'wan6'
	option device 'eth0.2'
	option proto 'dhcpv6'
config interface 'wwan'
	option proto 'dhcp'
	option metric '20'
EOF
uci set wireless.dn_uplink=wifi-iface; uci set wireless.dn_uplink.mode=sta; uci set wireless.dn_uplink.disabled=0; uci commit wireless
uci -q delete dn-net.state; uci commit dn-net; rm -f /etc/dn/router-mode.tgz
sums() { md5sum /etc/config/network /etc/config/dhcp /etc/config/wireless /etc/config/firewall | cut -d' ' -f1 | tr '\n' ' '; }
before=$(sums)
eq "mode-get: router by default" "$(j "$(net mode-get)" '@.mode')" "router"
r=$(net mode-set '{"mode":"bridge"}'); eq "bridge: exit" "$?" 0
eq "bridge: answers switching, via wired by default" "$(j "$r" '@.mode') $(j "$r" '@.via') $(j "$r" '@.status')" "bridge wired switching"
eq "bridge: the WAN port joins the LAN bridge" "$(uci get network.@device[0].ports)" "eth0.1 eth0.2"
eq "bridge: wan and wan6 are off" "$(uci get network.wan.auto) $(uci get network.wan6.auto)" "0 0"
eq "bridge: the LAN takes the boat's address by DHCP" "$(uci get network.lan.proto) $(uci -q get network.lan.ipaddr || echo none)" "dhcp none"
eq "bridge: no DHCP server, v4 or v6" "$(uci get dhcp.lan.ignore) $(uci get dhcp.lan.dhcpv6) $(uci get dhcp.lan.ra)" "1 disabled disabled"
eq "bridge: the Wi-Fi uplink is switched off" "$(uci get wireless.dn_uplink.disabled)" "1"
eq "bridge: the router-mode settings were saved" "$([ -s /etc/dn/router-mode.tgz ] && echo saved)" "saved"
eq "mode-get: bridge" "$(j "$(net mode-get)" '@.mode')" "bridge"
r=$(net mode-set '{"mode":"bridge"}'); eq "bridge again: a no-op, never a second port" "$(uci get network.@device[0].ports)" "eth0.1 eth0.2"
r=$(net mode-set '{"mode":"router"}'); eq "router: exit" "$?" 0
eq "router: every config back EXACTLY as it was" "$(sums)" "$before"
eq "router: mode-get router" "$(j "$(net mode-get)" '@.mode')" "router"
net mode-set '{"mode":"repeater"}' >/dev/null; eq "mode: an unknown mode is refused" "$?" 2
eq "mode: ...nothing staged" "$(staged)" 0
uci set dn-net.state=state; uci set dn-net.state.mode=bridge; uci commit dn-net; rm -f /etc/dn/router-mode.tgz
net mode-set '{"mode":"router"}' >/dev/null; eq "router: with no saved settings it is refused, never guessed" "$?" 2
uci set dn-net.state.mode=router; uci commit dn-net
uci delete network.wan.device; uci commit network
net mode-set '{"mode":"bridge"}' >/dev/null; eq "bridge: no WAN port to bridge is refused" "$?" 2
eq "bridge: ...and the LAN is untouched" "$(uci get network.lan.proto)" "static"
uci set network.wan.device=eth0.2; uci commit network
before=$(sums)

# mode-watch: an address from the boat keeps bridge mode; none in time reverts to router mode by itself.
WATCH=/t/feed/dn-net/files/usr/libexec/dn-net/mode-watch
net mode-set '{"mode":"bridge"}' >/dev/null
echo '{"up":true,"ipv4-address":[{"address":"192.168.86.114","mask":24}]}' > /tmp/fx/if.lan
DN_NET_WATCH_SECS=2 DN_NET_WATCH_STEP=1 sh "$WATCH"; eq "watch: an address from the boat keeps bridge mode" "$? $(j "$(net mode-get)" '@.mode')" "0 bridge"
rm -f /tmp/fx/if.lan
DN_NET_WATCH_SECS=2 DN_NET_WATCH_STEP=1 sh "$WATCH"; eq "watch: no address in time reverts" "$?" 1
eq "watch: ...to router mode, every config exactly as before" "$(j "$(net mode-get)" '@.mode') $(sums)" "router $before"

echo "admin-password"
export DN_NET_VERIFY_ROOT=/dnauth/verify-root DN_NET_WRONG_DELAY=0
vr() { printf '%s\n' "$1" | "$DN_NET_VERIFY_ROOT"; echo $?; }
sed -i 's/^root:[^:]*:/root::/' /etc/shadow
r=$(net admin-password '{"current":"","next":"first pass"}'); eq "no password yet: the empty current is right" "$? $(j "$r" '@.ok')" "0 true"
eq "...and the new one is root's now" "$(vr 'first pass')" 0
cp /etc/shadow /tmp/shadow.before
net admin-password '{"current":"not it","next":"x2345678"}' >/dev/null; eq "a wrong current password is refused" "$?" 2
eq "...saying so" "$(cat /tmp/err)" "the current password is wrong"
eq "...and nothing changed" "$(cmp -s /etc/shadow /tmp/shadow.before && echo same)" same
net admin-password '{"next":"x2345678"}' >/dev/null; eq "a missing current password is a wrong one" "$?" 2
P='a \"quoted\" \\ $HOME `id` é'
r=$(net admin-password "{\"current\":\"first pass\",\"next\":\"$P\"}"); eq "the right current password changes it" "$?" 0
eq "...to exactly the new one: quotes, backslash, \$, backticks, UTF-8" "$(vr 'a "quoted" \ $HOME `id` é')" 0
eq "...and the old one no longer works" "$(vr 'first pass')" 1
cp /etc/shadow /tmp/shadow.before
for body in '{"current":"x","next":""}' '{"current":"x"}' "{\"current\":\"x\",\"next\":\"a\\tb\"}" 'not json' \
            "{\"current\":\"x\",\"next\":\"$(head -c 129 /dev/zero | tr '\0' a)\"}" \
            "{\"current\":\"x\",\"next\":\"$(i=0; while [ $i -lt 65 ]; do printf 'é'; i=$((i + 1)); done)\"}"; do
	net admin-password "$body" >/dev/null; eq "refused ($(head -c 60 /tmp/err))" "$?" 2
done
eq "...and none of those changed anything" "$(cmp -s /etc/shadow /tmp/shadow.before && echo same)" same
r=$(net admin-password "{\"current\":\"$P\",\"next\":\"$(head -c 128 /dev/zero | tr '\0' b)\"}"); eq "128 bytes is allowed" "$?" 0
eq "...and it reads back" "$(vr "$(head -c 128 /dev/zero | tr '\0' b)")" 0
cp /etc/shadow /tmp/shadow.before
DN_NET_VERIFY_ROOT=/nonexistent net admin-password '{"current":"","next":"y2345678"}' >/dev/null
eq "no dn-auth: a failure, never an unchecked change" "$? $(cmp -s /etc/shadow /tmp/shadow.before && echo same)" "1 same"

echo "bridge via Wi-Fi (relayd)"
uci set wireless.dn_uplink.ssid=Boatnet; uci commit wireless
touch /tmp/relay.sh; export DN_NET_RELAY_PROTO=/tmp/relay.sh
rm -f /tmp/fx/if.wwan /tmp/fx/if.lan
before=$(sums)
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null; eq "wifi: an uplink with no address is refused" "$?" 2
eq "wifi: ...nothing staged, nothing changed" "$(staged) $(sums)" "0 $before"
echo '{"up":true,"ipv4-address":[{"address":"192.168.8.57","mask":24}]}' > /tmp/fx/if.wwan
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null; eq "wifi: a boat network overlapping the LAN is refused" "$? $(grep -c overlaps /tmp/err)" "2 1"
echo '{"up":true,"ipv4-address":[{"address":"192.168.0.57","mask":16}]}' > /tmp/fx/if.wwan
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null; eq "wifi: ...by the wider prefix too (a /16 around the LAN)" "$?" 2
echo '{"up":true,"ipv4-address":[{"address":"192.168.86.40","mask":24}]}' > /tmp/fx/if.wwan
DN_NET_RELAY_PROTO=/nonexistent net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null
eq "wifi: no relayd is a failure, and nothing changed" "$? $(sums)" "1 $before"
uci set wireless.dn_uplink.disabled=1; uci commit wireless
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null; eq "wifi: a switched-off uplink is refused" "$?" 2
uci set wireless.dn_uplink.disabled=0; uci commit wireless; before=$(sums)
net mode-set '{"mode":"bridge","via":"banana"}' >/dev/null; eq "bridge: an unknown via is refused" "$?" 2
r=$(net mode-set '{"mode":"bridge","via":"wifi"}'); eq "wifi: exit" "$?" 0
eq "wifi: answers bridge via wifi" "$(j "$r" '@.mode') $(j "$r" '@.via') $(j "$r" '@.status')" "bridge wifi switching"
eq "wifi: relayd joins the LAN and the Wi-Fi uplink" "$(uci get network.dn_relay.proto) $(uci get network.dn_relay.network)" "relay lan wwan"
eq "wifi: the LAN keeps its own static address" "$(uci get network.lan.proto) $(uci get network.lan.ipaddr)" "static 192.168.8.1"
eq "wifi: the WAN port is NOT bridged" "$(uci get network.@device[0].ports)" "eth0.1"
eq "wifi: ...it is off (no firewall, so it must face nothing)" "$(uci get network.wan.auto) $(uci get network.wan6.auto)" "0 0"
eq "wifi: no DHCP server, v4 or v6 (the boat's DHCP is relayed)" "$(uci get dhcp.lan.ignore) $(uci get dhcp.lan.dhcpv6) $(uci get dhcp.lan.ra)" "1 disabled disabled"
eq "wifi: the Wi-Fi uplink stays on" "$(uci get wireless.dn_uplink.disabled)" "0"
r=$(net mode-get); eq "mode-get: bridge via wifi, at its address on the boat's network" "$(j "$r" '@.mode') $(j "$r" '@.via') $(j "$r" '@.ip')" "bridge wifi 192.168.86.40"
net mode-set '{"mode":"bridge","via":"wired"}' >/dev/null; eq "wifi -> wired directly is refused (through router mode)" "$? $(uci get network.@device[0].ports)" "2 eth0.1"
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null; eq "wifi again: a no-op, never a second relay member" "$? $(uci get network.dn_relay.network)" "0 lan wwan"
r=$(net mode-set '{"mode":"router"}'); eq "router: exit" "$?" 0
eq "router: every config back EXACTLY as it was" "$(sums)" "$before"
eq "router: no via left behind" "$(uci -q get dn-net.state.via || echo none) $(j "$(net mode-get)" '@.via')" "none "
# mode-watch over Wi-Fi watches the Wi-Fi uplink, not the LAN: a LAN address must NOT keep it.
net mode-set '{"mode":"bridge","via":"wifi"}' >/dev/null
DN_NET_WATCH_SECS=2 DN_NET_WATCH_STEP=1 sh "$WATCH"; eq "watch wifi: an address on the Wi-Fi uplink keeps it" "$? $(j "$(net mode-get)" '@.via')" "0 wifi"
rm -f /tmp/fx/if.wwan; echo '{"up":true,"ipv4-address":[{"address":"192.168.8.1","mask":24}]}' > /tmp/fx/if.lan
DN_NET_WATCH_SECS=2 DN_NET_WATCH_STEP=1 sh "$WATCH"; eq "watch wifi: none there reverts, whatever the LAN has" "$?" 1
eq "watch wifi: ...to router mode, every config exactly as before, no via left" "$(j "$(net mode-get)" '@.mode') $(sums)$(uci -q get dn-net.state.via)" "router $before"
rm -f /tmp/fx/if.lan

echo "misc"
eq "reboot: answers first (nothing reboots in a test)" "$(j "$(net reboot)" '@.status')" "rebooting"
net frobnicate >/dev/null; eq "an unknown verb is a bad request" "$?" 2

[ "$fails" -eq 0 ] || { echo "net.test: $fails failure(s)"; exit 1; }
echo "net.test: all cases pass"
