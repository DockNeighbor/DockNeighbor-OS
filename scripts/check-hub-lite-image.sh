#!/bin/sh
# Prove the finished hub-lite image has every guarantee the profile promises, by opening the image itself
# (not the build's config). Fails on the first missing one.
#   usage: scripts/check-hub-lite-image.sh <sysupgrade.bin>
# Run against plain upstream OpenWrt for the same board, it must FAIL — that's how we know it can.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/profiles/hub-lite/profile.env"
img=$1
[ -f "$img" ] || { echo "check: no image $img" >&2; exit 1; }
fails=0
ok() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }

echo "check-hub-lite-image: $(basename "$img")"

# The vendor's sysupgrade accepts only an image whose metadata names its board.
meta=$(strings -n 16 "$img" | grep '"supported_devices"' | tail -1)
case "$meta" in *"\"$BOARD\""*) ok "metadata lists $BOARD" ;; *) bad "metadata does not list $BOARD" ;; esac

# Firmware partition of the board: 0xf90000 (/proc/mtd on the device, 2026-09-24).
size=$(wc -c < "$img"); max=$((0xf90000))
[ "$size" -le "$max" ] && ok "size $size <= $max" || bad "size $size > firmware partition $max"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# The rootfs follows the kernel; "hsqs" could also occur by chance in compressed data, so try each hit.
r=""
for off in $(grep -obUa hsqs "$img" | cut -d: -f1); do
  rm -rf "$tmp/r"
  # Unprivileged, unsquashfs can't create the image's device nodes and exits 2. Accept that, and ONLY that.
  rc=0; unsquashfs -q -n -o "$off" -d "$tmp/r" "$img" >"$tmp/u.log" 2>&1 || rc=$?
  if [ "$rc" -eq 2 ] && ! grep -v -e "could not create character device" -e "could not create block device" "$tmp/u.log" | grep -q .; then rc=0; fi
  if [ "$rc" -eq 0 ] && [ -d "$tmp/r/etc" ]; then r="$tmp/r"; break; fi
done
[ -n "$r" ] || { bad "no squashfs rootfs found"; echo "check: $fails failure(s)"; exit 1; }

grep -q 'ssh-ed25519' "$r/usr/sbin/dropbear" 2>/dev/null && ok "dropbear speaks ssh-ed25519" || bad "dropbear has no ssh-ed25519 (upstream small_flash build)"
[ -x "$r/usr/bin/brvg-hub-lite" ] && ok "hub-lite installed" || bad "hub-lite missing"
ls "$r"/etc/rc.d/S*brvg-hub-lite >/dev/null 2>&1 && ok "hub-lite enabled at boot" || bad "hub-lite not enabled"
[ -x "$r/www/brvg/api/hub" ] && ok "hub-lite /api/hub door present" || bad "hub-lite door missing"
[ -x "$r/usr/libexec/dn-handoff/apply" ] && [ -x "$r/etc/uci-defaults/05-dn-handoff" ] && ok "dn-handoff renderer present" || bad "dn-handoff missing"
[ -x "$r/etc/uci-defaults/95-dn-hub-lite" ] && ok "hub-lite feed setup at first boot" || bad "95-dn-hub-lite missing"
grep -q '^DN_OS_PROFILE=hub-lite$' "$r/etc/dn-release" 2>/dev/null && ok "dn-release: $(grep DN_OS_VERSION "$r/etc/dn-release")" || bad "no /etc/dn-release"
# Level 1 (the hub-lite package from its feed) is only safe if opkg refuses unsigned indexes.
grep -q '^option check_signature' "$r/etc/opkg.conf" 2>/dev/null && ok "opkg checks feed signatures (level 1)" || bad "opkg does not check signatures"
# Level 2 (the whole OS): the upgrader, the release key, the channel, and what must survive it.
[ -x "$r/usr/sbin/dn-os-upgrade" ] && ok "dn-os-upgrade present (level 2)" || bad "dn-os-upgrade missing"
[ -x "$r/usr/libexec/dn-net/mode-watch" ] && ok "bridge mode's self-revert watchdog present" || bad "dn-net mode-watch missing"
grep -q '^net.ipv4.conf.all.arp_ignore=1' "$r/etc/sysctl.d/90-dn-net.conf" 2>/dev/null && ok "no ARP flux between two uplinks on one network" || bad "arp_ignore not set"
[ -x "$r/usr/sbin/dn-pkg-upgrade" ] && [ -x "$r/etc/uci-defaults/94-dn-os-feed" ] && ok "dn-pkg-upgrade + dn_os feed setup (level 1, dn-* packages)" || bad "dn-pkg-upgrade or 94-dn-os-feed missing"
# Every dn-* package is a real package (so the dn_os feed can upgrade it), not loose image files.
for p in dn-handoff dn-os-upgrade dn-hub-lite-os dn-net; do
  [ -f "$r/usr/lib/opkg/info/$p.control" ] && ok "package installed: $p" || bad "not installed as a package: $p"
done
[ -f "$r/etc/dn/os-keys/3420e953f030f5a8" ] && ok "OS release key 3420e953f030f5a8" || bad "OS release key missing"
grep -q '^DN_OS_CHANNEL_URL=https://' "$r/etc/dn-release" 2>/dev/null && ok "OS channel set" || bad "no DN_OS_CHANNEL_URL"
kept=$(sed '/^#/d' "$r"/lib/upgrade/keep.d/* 2>/dev/null)
for f in /etc/brvg-hub-lite.conf /etc/brvg-hub-lite.keys /etc/dn/hub-lite.min; do
  echo "$kept" | grep -qxF "$f" && ok "kept across OS upgrades: $f" || bad "not kept across OS upgrades: $f"
done
echo "$kept" | grep -q '^/etc/dn/*$\|os-keys' && bad "OS keys would be kept across upgrades" || ok "OS keys owned by the image"
ls "$r"/etc/rc.d/S*dn-hub-lite-restore >/dev/null 2>&1 && ok "hub-lite restore after OS upgrade enabled" || bad "hub-lite restore not enabled"
# No local web page: the apps are the interface.
[ ! -d "$r/www/luci-static" ] && ok "no LuCI" || bad "LuCI is in the image"
ls "$r"/etc/rc.d/S*uhttpd >/dev/null 2>&1 && bad "system uhttpd enabled" || ok "system uhttpd disabled"
[ -x "$r/usr/sbin/uhttpd" ] && ok "uhttpd binary present (hub-lite's own instance)" || bad "uhttpd binary missing"
# OpenWrt's 24.10 release key + the dn_os feed key. The hub-lite key arrives via feed-setup at first boot.
keys=$(ls "$r/etc/opkg/keys" 2>/dev/null | tr '\n' ' ')
[ "$keys" = "1c44072d07e3e228 d310c6f2833e97f7 " ] && ok "opkg keys: $keys" || bad "unexpected opkg keys: '${keys}' (a local build key?)"

[ "$fails" -eq 0 ] || { echo "check: $fails failure(s)"; exit 1; }
echo "check: all guarantees hold"
