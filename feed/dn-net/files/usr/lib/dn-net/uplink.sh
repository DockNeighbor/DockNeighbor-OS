# dn-net's ONE implementation of the Wi-Fi uplink's firewall, sourced by dn-net (uplink-join) and dn-handoff (the
# one-step flash), so the security rule can't drift between them. Stages uci changes; the caller commits.
#
# The uplink's ROLE decides its firewall, not the fact that it's Wi-Fi (owner, 2026-09-25):
#   lan  the router joined the BOAT's own network (e.g. Starlink's Wi-Fi) to be the hub-lite: a device on that
#        LAN, whose Shellys and apps must reach its doors (8722, 8181, 22). Its own 'uplink' zone ACCEPTS input
#        like LAN and still NATs the router's own AP clients (the lan zone itself wouldn't).
#   wan  a Wi-Fi internet uplink, e.g. a marina's public Wi-Fi: untrusted, so the wan zone, which drops input.
#        Also the default: a wrong "restricted" gets noticed and fixed; a wrong "open" on a public hotspot is silent.
#
# dn_uplink_zone ROLE [NETWORK]   -> 0 staged | 1 a uci write failed | 2 unknown role | 3 no wan zone
dn_uplink_zone() {
	_dz_role=${1:-wan}; _dz_net=${2:-wwan}
	case "$_dz_role" in lan|wan) ;; *) return 2 ;; esac
	_dz_wan=$(uci -q show firewall | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='wan'$/\1/p")
	[ -n "$_dz_wan" ] && uci -q del_list "firewall.$_dz_wan.network=$_dz_net"
	uci -q del_list "firewall.dn_uplink.network=$_dz_net"
	if [ "$_dz_role" = wan ]; then
		[ -n "$_dz_wan" ] || return 3
		uci add_list "firewall.$_dz_wan.network=$_dz_net" || return 1
		return 0
	fi
	uci set firewall.dn_uplink=zone &&
	uci set firewall.dn_uplink.name=uplink &&
	uci add_list "firewall.dn_uplink.network=$_dz_net" &&
	uci set firewall.dn_uplink.input=ACCEPT &&
	uci set firewall.dn_uplink.output=ACCEPT &&
	uci set firewall.dn_uplink.forward=REJECT &&
	uci set firewall.dn_uplink.masq=1 &&
	uci set firewall.dn_uplink.mtu_fix=1 &&
	uci set firewall.dn_uplink_fwd=forwarding &&
	uci set firewall.dn_uplink_fwd.src=lan &&
	uci set firewall.dn_uplink_fwd.dest=uplink || return 1
	return 0
}

# The role the uplink currently has: lan | wan | none.
dn_uplink_role() {
	uci -q get firewall.dn_uplink.network | tr ' ' '\n' | grep -qx "${1:-wwan}" && { echo lan; return; }
	uci -q show firewall | grep -q "\.network=.*'${1:-wwan}'" && { echo wan; return; }
	echo none
}
