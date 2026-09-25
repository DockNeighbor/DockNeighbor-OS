#!/bin/sh
# Run dn-os-upgrade inside OpenWrt's own userland (usign, jsonfilter, uclient-fetch, opkg, uhttpd).
#   usage: sh feed/dn-os-upgrade/test/upgrade.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
IMAGE=${OPENWRT_ROOTFS:-openwrt/rootfs:x86-64-24.10.8}
docker run --rm -v "$root:/t:ro" "$IMAGE" /bin/sh /t/feed/dn-os-upgrade/test/in-openwrt.sh
