#!/bin/sh
# DockNeighbor handoff, GL.iNet 4.x reader. Runs ON the stock router, before the flash.
# Reads the router's roles (LAN, access point, uplink, LTE modem, reservations, admin password, SSH keys) and
# writes a brand-neutral site file (handoff/README.md) into a sysupgrade config tarball; dn-handoff in the
# DockNeighbor OS image applies it at first boot:
#   /tmp/dn-handoff.tgz  ->  sysupgrade -f /tmp/dn-handoff.tgz <image>
# Prints only non-secret fields. Secrets never leave the device except inside the tarball.
# No set -eu: jshn is not nounset-safe. The steps that matter are checked explicitly.
. /usr/share/libubox/jshn.sh

T=/tmp/dn-handoff; rm -rf "$T"; mkdir -p "$T/etc/dn" "$T/etc/dropbear"
g() { uci -q get "$1" || true; }

# The band of a Wi-Fi interface's radio: 2g | 5g | 6g, or nothing when the config doesn't say. GL.iNet 4.x on
# OpenWrt 23.05+ has the radio's `band`; older bases only `hwmode`; GL names the interfaces wifi2g / wifi5g.
band_of() {
	_d=$(g wireless.$1.device)
	case "$(g wireless.${_d:-x}.band | tr 'A-Z' 'a-z')" in 2g) echo 2g; return ;; 5g) echo 5g; return ;; 6g) echo 6g; return ;; esac
	case "$(g wireless.${_d:-x}.hwmode)" in 11a|11ac) echo 5g; return ;; 11b|11g) echo 2g; return ;; esac
	case "$1" in *5g) echo 5g ;; *2g) echo 2g ;; esac
}

# The access point on the LAN (GL names it wifi2g; the guest AP is not carried). On a dual-band router the 2.4 GHz
# one: the boat's Shellys and most IoT devices are 2.4 GHz only.
ap=""; ap2=""; up=""
for s in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-iface$/\1/p'); do
	[ "$(g wireless.$s.disabled)" = 1 ] && continue
	case "$(g wireless.$s.mode):$(g wireless.$s.network)" in
		ap:lan) [ -z "$ap" ] && ap=$s; [ -z "$ap2" ] && [ "$(band_of $s)" = 2g ] && ap2=$s ;;
		sta:*) [ -z "$up" ] && up=$s ;;
	esac
done
[ -n "$ap2" ] && ap=$ap2

# The LTE modem. GL.iNet 4.x keeps it as a network interface named after the modem's USB path (modem_1_1_2 on the
# GL-X750; its dhcpv6 child modem_1_1_2_6 is skipped), whatever its dial protocol (qmi, qcm, 3g ...). Some 4.x
# releases keep the SIM's settings in /etc/config/glmodem instead (one section per SIM, named by its ICCID).
lte=""
for s in $(uci -q show network | sed -n 's/^network\.\(modem_[^.=]*\)=interface$/\1/p'); do
	case "$(g network.$s.proto)" in dhcp|dhcpv6|static|none) continue ;; esac
	lte=network.$s; break
done
if [ -z "$lte" ]; then
	for s in $(uci -q show glmodem | sed -n 's/^glmodem\.\([^.=]*\)=.*/\1/p'); do
		[ -n "$(g glmodem.$s.apn)$(g glmodem.$s.proto)" ] && { lte=glmodem.$s; break; }
	done
fi
lte_auth=""; lte_warn=""
if [ -n "$lte" ]; then
	# GL shows NONE / PAP / CHAP / PAP/CHAP; OpenWrt's qmi (uqmi) takes none / pap / chap / both.
	a=$(g $lte.auth)
	case "$(echo "$a" | tr 'A-Z' 'a-z')" in
		""|none) lte_auth=none ;;
		pap) lte_auth=pap ;;
		chap) lte_auth=chap ;;
		both|pap/chap|pap_chap|papchap|pap-chap) lte_auth=both ;;
		*) lte_warn="$lte_warn auth '$a' not carried;" ;;
	esac
	# IP type: OpenWrt's pdptype, or GL's ip_type (IPV4V6 / IP / IPV6).
	t=$(g $lte.pdptype); [ -n "$t" ] || t=$(g $lte.ip_type)
	case "$(echo "$t" | tr 'A-Z' 'a-z')" in
		"") lte_pdp="" ;;
		ip|ipv4) lte_pdp=ipv4 ;;
		ipv6) lte_pdp=ipv6 ;;
		ipv4v6) lte_pdp=ipv4v6 ;;
		*) lte_pdp=""; lte_warn="$lte_warn ip type '$t' not carried;" ;;
	esac
	# The SIM PIN: on the interface, or (4.x releases that keep it per SIM) the one SIM section that has one.
	lte_pin=$(g $lte.pincode); [ -n "$lte_pin" ] || lte_pin=$(g $lte.pin_code)
	if [ -z "$lte_pin" ]; then
		pins=$(uci -q show glmodem | sed -n "s/^glmodem\.[^.]*\.pincode='\(.*\)'$/\1/p" | grep -v '^$')
		[ "$(echo "$pins" | grep -c .)" = 1 ] && lte_pin=$pins
	fi
	[ -z "$lte_pin" ] || echo "$lte_pin" | grep -qxE '[0-9]{4,8}' || { lte_pin=""; lte_warn="$lte_warn a SIM PIN that is not 4 to 8 digits not carried;"; }
fi

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
		b=$(band_of $ap); [ -n "$b" ] && json_add_string band "$b"
	json_close_object
fi
# The uplink. BSSID is deliberately NOT carried: pinning one access point breaks on a mesh or a new berth.
if [ -n "$up" ]; then
	json_add_object uplink
		json_add_string type wifi
		json_add_string ssid "$(g wireless.$up.ssid)"
		json_add_string enc "$(g wireless.$up.encryption)"
		json_add_string key "$(g wireless.$up.key)"
		# lan = this router joins the boat's own network as the hub-lite; wan = a Wi-Fi internet uplink
		# (e.g. a marina). The vendor config can't tell them apart, so the app says which: UPLINK_ROLE.
		# Unset leaves it to the firmware's default (wan: restricted).
		[ -n "${UPLINK_ROLE:-}" ] && json_add_string role "$UPLINK_ROLE"
		b=$(band_of $up); [ -n "$b" ] && json_add_string band "$b"
	json_close_object
fi
if [ -n "$lte" ]; then
	json_add_object lte
		json_add_string apn "$(g $lte.apn)"
		[ -n "$lte_pin" ] && json_add_string pincode "$lte_pin"
		[ -n "$lte_auth" ] && json_add_string auth "$lte_auth"
		if [ -n "$lte_auth" ] && [ "$lte_auth" != none ]; then
			json_add_string username "$(g $lte.username)"
			json_add_string password "$(g $lte.password)"
		fi
		[ -n "$lte_pdp" ] && json_add_string pdptype "$lte_pdp"
		[ "$(g $lte.disabled)" = 1 ] && json_add_boolean disabled 1
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
# The SIM PIN and the APN password are secrets: only whether they're there.
[ -n "$lte" ] && echo "lte ($lte) apn '$(f @.lte.apn)' auth:$(f @.lte.auth) pin:$([ -n "$(f @.lte.pincode)" ] && echo set || echo none) password:$(f @.lte.password | wc -c | tr -d ' ')B${lte_warn:+ WARNING:$lte_warn}"
rm -f /tmp/dn-site.$$
echo "tarball:"; tar tzf /tmp/dn-handoff.tgz
