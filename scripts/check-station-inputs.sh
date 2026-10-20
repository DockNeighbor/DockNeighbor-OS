#!/bin/sh
# Check that station/ is usable source for the station image:
#   1. station/openwrt/VERSION's tag is the pinned commit;
#   2. the board patches apply to it, in order;
#   3. the build config selects the SenseCAP M2 with the patches in, and NOT without them (so this check can fail),
#      along with the radio from the pinned ChirpStack feed.
# DockNeighbor's own feed is private and is not used here, so defconfig drops its dn-* lines; nothing below needs them.
#   usage: scripts/check-station-inputs.sh   (Linux with OpenWrt's host tools; WORK_DIR defaults to ./build/station-check)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
st=$root/station
fail() { echo "check-station-inputs: $*" >&2; exit 1; }

. "$st/openwrt/VERSION"
. "$st/build-inputs.env"
for v in OPENWRT_REPO OPENWRT_TAG OPENWRT_COMMIT CHIRPSTACK_FEED; do
  eval "[ -n \"\${$v:-}\" ]" || fail "$v is not set"
done
hex40() { [ "${#1}" -eq 40 ] && case "$1" in *[!0-9a-f]*) false ;; *) true ;; esac; }
hex40 "$OPENWRT_COMMIT" || fail "OPENWRT_COMMIT '$OPENWRT_COMMIT' is not a full commit id"
hex40 "${CHIRPSTACK_FEED##*^}" || fail "CHIRPSTACK_FEED is not pinned to a full commit id ('$CHIRPSTACK_FEED')"
ls "$st"/openwrt/patches/*.patch >/dev/null 2>&1 || fail "no patches in station/openwrt/patches/"
[ -f "$st/openwrt/bootstrap.diffconfig" ] || fail "no station/openwrt/bootstrap.diffconfig"

work=${WORK_DIR:-$root/build/station-check}; src=$work/openwrt
rm -rf "$src"; mkdir -p "$work"
git clone -q --depth 1 -b "$OPENWRT_TAG" "$OPENWRT_REPO" "$src"
head=$(git -C "$src" rev-parse HEAD)
[ "$head" = "$OPENWRT_COMMIT" ] || fail "$OPENWRT_TAG is $head, not the pinned $OPENWRT_COMMIT"
cd "$src"
{ cat feeds.conf.default; echo "src-git chirpstack $CHIRPSTACK_FEED"; } > feeds.conf
./scripts/feeds update -a > "$work/feeds.log" 2>&1 || { cat "$work/feeds.log"; fail "feeds update failed"; }
./scripts/feeds install -a >> "$work/feeds.log" 2>&1 || { cat "$work/feeds.log"; fail "feeds install failed"; }

DEVICE_SYM=CONFIG_TARGET_ramips_mt76x8_DEVICE_sensecap_wm7628n
# defconfig from the station's diffconfig; fails the script (not just returns) if defconfig itself fails.
defconfig() {
  rm -rf tmp
  cp "$st/openwrt/bootstrap.diffconfig" .config
  make defconfig > "$work/defconfig.log" 2>&1 || { cat "$work/defconfig.log"; fail "make defconfig failed"; }
  grep -qx 'CONFIG_TARGET_ramips_mt76x8=y' .config || fail "defconfig did not keep the ramips/mt76x8 target"
}

defconfig
if grep -qx "$DEVICE_SYM=y" .config; then fail "plain OpenWrt $OPENWRT_TAG already selects the M2: this check cannot fail"; fi
echo "check-station-inputs: without the patches, $DEVICE_SYM is not selected (as it must be)"

for p in "$st"/openwrt/patches/*.patch; do
  git -c user.name=check -c user.email=check@localhost am -q --3way "$p" || fail "$(basename "$p") does not apply"
  echo "check-station-inputs: applied $(basename "$p")"
done

defconfig
grep -qx "$DEVICE_SYM=y" .config || fail "with the patches, the config does not select the SenseCAP M2 ($DEVICE_SYM)"
grep -qx 'CONFIG_PACKAGE_chirpstack-concentratord-target-seeed-sensecap-m2=m' .config ||
  fail "the radio (chirpstack-concentratord-target-seeed-sensecap-m2) is not selected from the ChirpStack feed"
# Each file in station/openwrt/files/ replaces one OpenWrt ships.
(cd "$st/openwrt/files" && find . -type f) | while read -r f; do
  f=${f#./}
  [ -n "$(find package -path "*/files/$f" -type f 2>/dev/null | head -1)" ] || fail "station/openwrt/files/$f replaces no OpenWrt file"
done
echo "check-station-inputs: OK — OpenWrt $OPENWRT_TAG ($OPENWRT_COMMIT), $(ls "$st"/openwrt/patches/*.patch | wc -l | tr -d ' ') patch(es), the M2 and its radio selected"
