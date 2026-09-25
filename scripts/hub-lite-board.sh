# Sourced by the hub-lite scripts (needs $root): the profile, its shared upstream pins, and ONE board's pins.
# The profile is the role (the router runs the hub-lite); the board is a variable: profiles/hub-lite/boards/<device>/.
#   hub_lite_boards          the boards' device names, one per line, sorted (the MT300N-V2 first)
#   hub_lite_load <device>   source profile.env, upstream.env and boards/<device>/board.env; fail on an unknown or
#                            incomplete board
prof="$root/profiles/hub-lite"

hub_lite_boards() {
	for f in "$prof"/boards/*/board.env; do [ -f "$f" ] && basename "$(dirname "$f")"; done | sort
}

hub_lite_load() {
	[ -n "${1:-}" ] && [ -f "$prof/boards/$1/board.env" ] ||
		{ echo "hub-lite: unknown board '${1:-}' (boards: $(hub_lite_boards | tr '\n' ' '))" >&2; return 1; }
	BOARD_PACKAGES=""
	. "$prof/upstream.env"
	. "$prof/profile.env"
	. "$prof/boards/$1/board.env"
	[ "$DEVICE" = "$1" ] || { echo "hub-lite: boards/$1/board.env says DEVICE=$DEVICE" >&2; return 1; }
	for _v in OPENWRT_VERSION OPENWRT_COMMIT OPENWRT_TARGET OPENWRT_BASE PKG_ARCH SDK_FILE SDK_SHA256 IB_FILE IB_SHA256 \
		UPSTREAM_IMAGE_FILE UPSTREAM_IMAGE_SHA256 BOARD FIRMWARE_SIZE DN_OS_CHANNEL_URL DN_OS_VERSION HUB_LITE_VERSION; do
		eval "_x=\${$_v:-}"
		[ -n "$_x" ] || { echo "hub-lite: $_v is not set for board $1" >&2; return 1; }
	done
	# The release workflow publishes each board's signed manifest as channel-hub-lite/<device>.json, and a router
	# reads the URL baked into its image: the two must name the same file.
	case "$DN_OS_CHANNEL_URL" in
		https://github.com/DockNeighbor/DockNeighbor-OS/releases/download/channel-hub-lite/"$DEVICE".json) ;;
		*) echo "hub-lite: board $1's DN_OS_CHANNEL_URL is not channel-hub-lite/$DEVICE.json" >&2; return 1 ;;
	esac
	# Every board of this profile is the same OpenWrt release.
	case "$OPENWRT_BASE" in
		https://downloads.openwrt.org/releases/"$OPENWRT_VERSION"/targets/"$OPENWRT_TARGET") ;;
		*) echo "hub-lite: board $1's OPENWRT_BASE is not OpenWrt $OPENWRT_VERSION $OPENWRT_TARGET" >&2; return 1 ;;
	esac
}
