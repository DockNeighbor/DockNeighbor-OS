#!/bin/sh
# DockNeighbor handoff, GL.iNet 4.x reader. Runs ON the stock router, before the flash.
# Reads the router's roles (LAN, access point, uplink, reservations, admin password, SSH keys) and
# writes a brand-neutral site file (handoff/README.md) into a sysupgrade config tarball; dn-handoff in the
# DockNeighbor OS image applies it at first boot:
#   /tmp/dn-handoff.tgz  ->  sysupgrade -f /tmp/dn-handoff.tgz <image>
# Prints only non-secret fields. Secrets never leave the device except inside the tarball.
# No set -eu: jshn is not nounset-safe. The steps that matter are checked explicitly.
. /usr/share/libubox/jshn.sh

T=/tmp/dn-handoff; rm -rf "$T"; mkdir -p "$T/etc/dn" "$T/etc/dropbear"
g() { uci -q get "$1" || true; }

# The access point on the LAN (GL names it wifi2g; the guest AP is not carried).
ap=""; up=""
for s in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-iface$/\1/p'); do
	[ "$(g wireless.$s.disabled)" = 1 ] && continue
	case "$(g wireless.$s.mode):$(g wireless.$s.network)" in
		ap:lan) [ -z "$ap" ] && ap=$s ;;
		sta:*) [ -z "$up" ] && up=$s ;;
	esac
done

json_init
json_add_int v 1
json_add_string source "glinet $(cat /etc/glversion 2>/dev/null) $(cat /tmp/sysinfo/board_name)"
json_add_object lan
	json_add_string ip "$(g network.lan.ipaddr)"
	json_add_string mask "$(g network.lan.netmask)"
json_close_object
dev=$(g wireless.${ap:-x}.device)
json_add_string country "$(g wireless.${dev:-x}.country)"
if [ -n "$ap" ]; then
	json_add_object ap
		json_add_string ssid "$(g wireless.$ap.ssid)"
		json_add_string enc "$(g wireless.$ap.encryption)"
		json_add_string key "$(g wireless.$ap.key)"
	json_close_object
fi
# The uplink. BSSID is deliberately NOT carried: pinning one access point breaks on a mesh or a new berth.
if [ -n "$up" ]; then
	json_add_object uplink
		json_add_string type wifi
		json_add_string ssid "$(g wireless.$up.ssid)"
		json_add_string enc "$(g wireless.$up.encryption)"
		json_add_string key "$(g wireless.$up.key)"
	json_close_object
fi
json_add_array reservations
for h in $(uci -q show dhcp | sed -n 's/^dhcp\.\([^.=]*\)=host$/\1/p'); do
	json_add_object
		json_add_string name "$(g dhcp.$h.name)"
		json_add_string mac "$(g dhcp.$h.mac)"
		json_add_string ip "$(g dhcp.$h.ip)"
	json_close_object
done
json_close_array
json_add_string rootHash "$(sed -n 's/^root:\([^:]*\):.*/\1/p' /etc/shadow)"

umask 077
json_dump > "$T/etc/dn/site.json"
cp /etc/dropbear/authorized_keys "$T/etc/dropbear/" 2>/dev/null || true
cp /etc/dropbear/dropbear_ed25519_host_key "$T/etc/dropbear/" 2>/dev/null || true
# A router already running the hub-lite keeps its enrollment (device token, member keys) across the flash.
for f in /etc/brvg-hub-lite.conf /etc/brvg-hub-lite.keys; do [ -f "$f" ] && cp -p "$f" "$T/etc/"; done
[ -s "$T/etc/dn/site.json" ] || { echo "handoff incomplete" >&2; exit 1; }
tar czf /tmp/dn-handoff.tgz -C "$T" etc || { echo "tar failed" >&2; exit 1; }
rm -rf "$T"

# Non-secret summary for whoever ran this.
tar xzOf /tmp/dn-handoff.tgz etc/dn/site.json > /tmp/dn-site.$$ && chmod 600 /tmp/dn-site.$$
f() { jsonfilter -i /tmp/dn-site.$$ -e "$1" 2>/dev/null; }
echo "lan $(f @.lan.ip)/$(f @.lan.mask)"
[ -n "$(f @.ap.ssid)" ] && echo "ap '$(f @.ap.ssid)' $(f @.ap.enc) key:$(f @.ap.key | wc -c | tr -d ' ')B"
[ -n "$(f @.uplink.ssid)" ] && echo "uplink '$(f @.uplink.ssid)' $(f @.uplink.enc) key:$(f @.uplink.key | wc -c | tr -d ' ')B"
rm -f /tmp/dn-site.$$
echo "tarball:"; tar tzf /tmp/dn-handoff.tgz
