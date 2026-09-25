#!/bin/sh
# Write and sign out/hub-lite/<device>/manifest.json for a release: what dn-os-upgrade on a router of that board
# trusts. The release workflow publishes it as channel-hub-lite/<device>.json, the URL baked into that board's image.
#   usage: scripts/release-manifest.sh <tag> <secret key file, named *.sec> <device>
# DN_OS_VERIFY_PUB overrides the public key it verifies against (CI's dry run signs with a throwaway key).
# The manifest names the image by its release URL, sha256 and size; the signature covers all of it.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/hub-lite-board.sh"
tag=$1; key=$2; hub_lite_load "${3:-}"
out="$root/out/hub-lite/$DEVICE"
img=$(ls "$out"/*-"$DEVICE"-squashfs-sysupgrade.bin)
[ "$(echo "$img" | wc -l)" -eq 1 ] || { echo "release: expected exactly one $DEVICE image in $out" >&2; exit 1; }
name=$(basename "$img")
python3 - "$out/manifest.json" <<EOF
import json, sys
json.dump({
  "profile": "hub-lite",
  "board": "$BOARD",
  "version": "$DN_OS_VERSION",
  "hubLite": "$HUB_LITE_VERSION",
  "upstream": "OpenWrt $OPENWRT_VERSION $OPENWRT_TARGET",
  "image": "https://github.com/DockNeighbor/DockNeighbor-OS/releases/download/$tag/$name",
  "sha256": "$(sha256sum "$img" | cut -d' ' -f1)",
  "size": $(wc -c < "$img"),
}, open(sys.argv[1], "w"), indent=2)
EOF
signify-openbsd -S -s "$key" -m "$out/manifest.json" -x "$out/manifest.json.sig"
# Prove the signature against the key routers carry, not just the one we signed with.
signify-openbsd -V -q -p "${DN_OS_VERIFY_PUB:-$root/feed/dn-os-upgrade/files/etc/dn/os-keys/3420e953f030f5a8}" -m "$out/manifest.json" -x "$out/manifest.json.sig" ||
  { echo "release: the manifest does not verify against the key baked into images" >&2; exit 1; }
cat "$out/manifest.json"
