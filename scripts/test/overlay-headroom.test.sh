#!/bin/sh
# Does overlay_headroom put rootfs_data where the kernel does, and take off jffs2's reserve?
#   usage: sh scripts/test/overlay-headroom.test.sh
# Synthetic images: a squashfs superblock ("hsqs", bytes_used at +40) at a chosen offset. The expected numbers are
# worked by hand in the comments, not computed by the code under test.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
. "$root/scripts/overlay-headroom.sh"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }

# le64 N: N as 8 little-endian bytes.
le64() { n=$1; i=0; while [ "$i" -lt 8 ]; do printf "\\$(printf %03o $((n & 255)))"; n=$((n >> 8)); i=$((i + 1)); done; }
# image FILE OFFSET BYTES_USED: zeros, then a superblock at OFFSET.
image() {
	dd if=/dev/zero of="$1" bs=1 count="$2" 2>/dev/null
	{ printf "${MAGIC:-hsqs}"; dd if=/dev/zero bs=1 count=36 2>/dev/null; le64 "$3"; dd if=/dev/zero bs=1 count=48 2>/dev/null; } >> "$1"
}

# Unaligned squashfs (ramips puts it straight after the kernel): 0x1234 + 0x30000 = 201268, up to the next 64 KiB
# block = 262144. Overlay 0x100000 - 262144 = 786432 = 12 blocks. Reserve: 2 + ceil((786432/50 + 12*100) / 65536)
# = 2 + ceil(16928 / 65536) = 3 blocks. Usable 9 blocks = 589824.
image "$W/a.bin" $((0x1234)) $((0x30000))
eq "unaligned squashfs rounds up to the erase block" "$(overlay_headroom "$W/a.bin" $((0x1234)) 0x100000 0x10000)" "262144 786432 589824"

# Ending exactly on a block: no extra block. 0x10000 + 0x20000 = 0x30000 = 196608. Overlay 0x400000 - 196608 =
# 3997696 = 61 blocks. Reserve: 2 + ceil((79953 + 6100) / 65536) = 4. Usable 57 blocks = 3735552.
image "$W/b.bin" $((0x10000)) $((0x20000))
eq "aligned squashfs takes no extra block" "$(overlay_headroom "$W/b.bin" $((0x10000)) 0x400000 0x10000)" "196608 3997696 3735552"

# A squashfs that fills the partition leaves nothing.
eq "a full partition leaves no overlay" "$(overlay_headroom "$W/b.bin" $((0x10000)) 0x30000 0x10000)" "196608 0 0"
# Two blocks of overlay are all reserve.
eq "an overlay smaller than the reserve is zero usable" "$(overlay_headroom "$W/b.bin" $((0x10000)) 0x50000 0x10000)" "196608 131072 0"

# No superblock at the offset: refuse, never guess.
if overlay_headroom "$W/b.bin" 0 0x400000 0x10000 >/dev/null 2>&1; then bad "an offset with no squashfs was measured"; else pass "an offset with no squashfs is refused"; fi

# A size where the superblock would be, but not its magic: still refused, so a stray hit can't be measured.
MAGIC=hsqX image "$W/c.bin" $((0x10000)) $((0x20000))
if overlay_headroom "$W/c.bin" $((0x10000)) 0x400000 0x10000 >/dev/null 2>&1; then bad "a block without the squashfs magic was measured"; else pass "a block without the squashfs magic is refused"; fi

[ "$fails" -eq 0 ] || { echo "overlay-headroom: $fails failure(s)"; exit 1; }
echo "overlay-headroom: all pass"
