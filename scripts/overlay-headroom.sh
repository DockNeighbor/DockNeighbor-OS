# Sourced by check-hub-lite-image.sh and its test: how much writable overlay an image leaves on its board.
#   overlay_headroom <image> <squashfs offset> <firmware size> <erase size>
#     prints "<rootfs_data offset> <overlay bytes> <usable bytes>"; fails on an image with no squashfs there
#
# The image fits the firmware partition, but what installs or upgrades later (a level-1 package, the hub's
# state) lands in rootfs_data, the jffs2 overlay. The kernel puts rootfs_data at the end of the squashfs,
# rounded up to an erase block (OpenWrt's mtd rootfs_data split: offset + bytes_used, padded to the
# erasesize), and it runs to the end of the firmware partition. The image's offsets are the partition's,
# since the partition starts on an erase block.
#
# jffs2 refuses writes below a reserve (fs/jffs2/build.c, jffs2_calc_trigger_levels): 2 blocks for
# deletions, plus 2% of the medium and 100 bytes per block, rounded up to blocks. "usable" is what is left
# above it, before jffs2's compression, so a file's real cost there is at most its size.
overlay_headroom() {
	[ "$(dd if="$1" bs=1 skip="$2" count=4 2>/dev/null)" = hsqs ] || { echo "overlay: no squashfs at offset $2 of $1" >&2; return 1; }
	# bytes_used: the superblock's little-endian u64 at +40 (od reads host order; CI and our Macs are little-endian).
	_used=$(od -An -t u8 -j $(($2 + 40)) -N 8 "$1" | tr -d ' ')
	[ -n "$_used" ] && [ "$_used" -gt 0 ] || { echo "overlay: can't read the squashfs size in $1" >&2; return 1; }
	_eb=$(($4)); _end=$(($2 + _used))
	_start=$(((_end + _eb - 1) / _eb * _eb))
	_ov=$(($3 - _start))
	[ "$_ov" -gt 0 ] || { echo "$_start 0 0"; return 0; }
	_blocks=$((_ov / _eb))
	_resv=$((2 + (_ov / 50 + _blocks * 100 + _eb - 1) / _eb))
	_usable=$(((_blocks - _resv) * _eb))
	[ "$_usable" -gt 0 ] || _usable=0
	echo "$_start $_ov $_usable"
}
