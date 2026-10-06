#!/bin/sh
# Inside an OpenWrt rootfs container (feed/dn-status/test/status.test.sh): the real status script against real uci,
# jshn and jsonfilter. No netifd, radios or routes in a container, so ifstatus, ubus, `ip route` and pgrep are stubs
# fed from fixtures in the shapes the router prints. The clock is DN_STATUS_NOW.
ST=/t/feed/dn-status/files/usr/libexec/dn-status/status
mkdir -p /tmp/stub /tmp/fx /tmp/sysinfo /etc/config
# The rootfs may ship without a network config; the script reads network.lte from uci, committed.
[ -f /etc/config/network ] || touch /etc/config/network
export PATH=/tmp/stub:$PATH DN_STATUS_HUB=/tmp/fx/hub.json DN_STATUS_RELEASE=/tmp/fx/dn-release DN_STATUS_NOW=1800000000
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }
j() { jsonfilter -s "$OUT" -e "$1"; }
run() { OUT=$(sh "$ST" 2>/tmp/err); [ -s /tmp/err ] && { bad "stderr: $(cat /tmp/err)"; }; }

cat > /tmp/stub/ip <<'S'
#!/bin/sh
[ "$*" = "-4 route show default" ] && { cat /tmp/fx/route 2>/dev/null; exit 0; }
exec /sbin/ip "$@"
S
cat > /tmp/stub/ifstatus <<'S'
#!/bin/sh
[ -f "/tmp/fx/if.$1" ] && cat "/tmp/fx/if.$1" || { echo "Interface $1 not found" >&2; exit 1; }
S
cat > /tmp/stub/ubus <<'S'
#!/bin/sh
[ "$*" = "call network.wireless status" ] && [ -f /tmp/fx/wireless ] && { cat /tmp/fx/wireless; exit 0; }
exit 4
S
cat > /tmp/stub/pgrep <<'S'
#!/bin/sh
[ -f /tmp/fx/hub-running ]
S
chmod +x /tmp/stub/*
echo 'glinet,gl-x750' > /tmp/sysinfo/board_name
printf 'DN_OS_PROFILE=hub-lite\nDN_OS_VERSION=0.1.6\nDN_OS_UPSTREAM="OpenWrt 24.10.8 ath79/generic"\n' > /tmp/fx/dn-release
AP='{"radio0":{"up":true,"interfaces":[{"section":"default_radio0","ifname":"phy0-ap0","config":{"mode":"ap","ssid":"Boatnet","key":"s3cret-wifi"}}]}}'
AP_STA='{"radio0":{"up":true,"interfaces":[{"ifname":"phy0-ap0","config":{"mode":"ap","ssid":"Boatnet","key":"s3cret-wifi"}},{"ifname":"phy0-sta0","config":{"mode":"sta","ssid":"Marina","key":"marina-pass"}}]}}'
hub() { printf '{"v":1,"hub":"hub-lite","version":"0.18.11","tickAt":%s,"tickEveryS":60,"cloudOkAt":%s,"cloudFailAt":%s}\n' "$1" "$2" "$3" > /tmp/fx/hub.json; }
reset() { rm -f /tmp/fx/route /tmp/fx/if.* /tmp/fx/wireless /tmp/fx/hub.json /tmp/fx/hub-running; uci -q delete network.lte; uci commit network; true; }

echo "wired, Wi-Fi AP up, a fresh hub whose last report succeeded"
reset
echo 'default via 192.168.1.1 dev eth0.2 proto static src 192.168.1.40' > /tmp/fx/route
echo "$AP" > /tmp/fx/wireless
hub 1799999990 1799999700 1799999000
run
eq "v" "$(j @.v)" 1
eq "os version" "$(j @.os.version)" 0.1.6
eq "board" "$(j @.os.board)" glinet,gl-x750
eq "internet up" "$(j @.internet.up)" true
eq "via wired" "$(j @.internet.via)" wired
eq "no cellular modem" "$(j @.cellular.present)" false
eq "AP up" "$(j @.wifi.ap)" up
eq "no Wi-Fi uplink configured" "$(j @.wifi.uplink)" none
eq "no LoRa on a router" "$(j @.lora.present)" false
eq "hub running" "$(j @.hub.state)" running
eq "hub version" "$(j @.hub.version)" 0.18.11
eq "cloud connected" "$(j @.cloud.state)" connected
eq "last report 300 s ago" "$(j @.cloud.okAgoS)" 300

echo "no secrets and no names: SSIDs, Wi-Fi keys, tokens and addresses never appear"
echo 'DEVICE_TOKEN="a1b2c3d4"' > /etc/brvg-hub-lite.conf
run
for s in Boatnet s3cret-wifi a1b2c3d4 192.168.1 ssid key; do
	case "$OUT" in *"$s"*) bad "output carries '$s'" ;; *) pass "no '$s'" ;; esac
done
rm -f /etc/brvg-hub-lite.conf

echo "the hub's last report failed"
hub 1799999990 1799999000 1799999700
run
eq "cloud not connected" "$(j @.cloud.state)" disconnected
eq "still says when it last worked" "$(j @.cloud.okAgoS)" 1000
hub 1799999990 0 1799999700
run
eq "never reported: not connected" "$(j @.cloud.state)" disconnected
eq "no last-report age" "$(j @.cloud.okAgoS)" ""

echo "a hub that stopped ticking (three ticks, 180 s, have passed) is stopped, and so is its cloud link"
hub 1799999819 1799999819 0
run
eq "181 s since the last tick: stopped" "$(j @.hub.state)" stopped
eq "cloud follows the hub" "$(j @.cloud.state)" disconnected
hub 1799999820 1799999820 0
run
eq "180 s: still running" "$(j @.hub.state)" running
printf '{"v":1,"tickAt":1799999870,"cloudOkAt":1799999870,"cloudFailAt":0}\n' > /tmp/fx/hub.json
run
eq "no tickEveryS: 300 s ticks (900 s stale), still running" "$(j @.hub.state)" running

echo "no hub status file: the process decides the hub, and the cloud is unknown — never a pass"
rm -f /tmp/fx/hub.json
touch /tmp/fx/hub-running
run
eq "hub-lite process: running" "$(j @.hub.state)" running
eq "cloud unknown" "$(j @.cloud.state)" unknown
rm -f /tmp/fx/hub-running
run
eq "no process, no hub-lite installed: unknown" "$(j @.hub.state)" unknown
echo 'not json' > /tmp/fx/hub.json
touch /tmp/fx/hub-running
run
eq "an unreadable status file falls back to the process" "$(j @.hub.state)" running
eq "and the cloud stays unknown" "$(j @.cloud.state)" unknown
printf '{"v":2,"tickAt":1799999990,"cloudOkAt":1799999990,"cloudFailAt":0}\n' > /tmp/fx/hub.json
run
eq "a status file of another version is not trusted" "$(j @.cloud.state)" unknown

echo "cellular: the X750's QMI modem carries the default route"
reset
uci set network.lte=interface; uci set network.lte.proto=qmi; uci commit network
eq "fixture: the modem is configured" "$(uci -q get network.lte.proto)" qmi
echo 'default dev wwan0 proto static scope link src 10.64.1.2 metric 30' > /tmp/fx/route
echo '{"up":true,"l3_device":"wwan0","uptime":3600}' > /tmp/fx/if.lte
echo "$AP" > /tmp/fx/wireless
run
eq "via cellular" "$(j @.internet.via)" cellular
eq "modem present" "$(j @.cellular.present)" true
eq "modem up" "$(j @.cellular.up)" true
echo '{"up":false}' > /tmp/fx/if.lte; : > /tmp/fx/route
run
eq "modem down" "$(j @.cellular.up)" false
eq "no route: internet down" "$(j @.internet.up)" false
eq "no route: via none" "$(j @.internet.via)" none

echo "Wi-Fi uplink (marina Wi-Fi) carries the default route"
reset
echo 'default via 10.0.0.1 dev phy0-sta0 proto static src 10.0.0.23 metric 20' > /tmp/fx/route
echo "$AP_STA" > /tmp/fx/wireless
echo '{"up":true,"l3_device":"phy0-sta0"}' > /tmp/fx/if.wwan
run
eq "via wifi" "$(j @.internet.via)" wifi
eq "uplink up" "$(j @.wifi.uplink)" up
echo '{"up":false}' > /tmp/fx/if.wwan
run
eq "uplink down" "$(j @.wifi.uplink)" down
case "$OUT" in *Marina*|*marina-pass*) bad "the uplink's SSID or key leaked" ;; *) pass "the uplink's name and key stay out" ;; esac

echo "radios down, or no answer from the radio service"
printf '{"radio0":{"up":false,"interfaces":[{"ifname":"phy0-ap0","config":{"mode":"ap"}}]}}' > /tmp/fx/wireless
run
eq "radio down: AP down" "$(j @.wifi.ap)" down
rm -f /tmp/fx/wireless
run
eq "no answer: unknown, never up" "$(j @.wifi.ap)" unknown

echo "as a CGI"
OUT=$(REQUEST_METHOD=GET sh "$ST" | head -1 | tr -d '\r')
eq "JSON content type first" "$OUT" "Content-Type: application/json"

[ "$fails" -eq 0 ] || { echo "dn-status: $fails failure(s)"; exit 1; }
echo "dn-status: all pass"
