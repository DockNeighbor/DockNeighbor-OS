#!/bin/sh
# Run dn-net inside OpenWrt's own userland (uci, jshn, jsonfilter): see in-openwrt.sh.
#   usage: sh feed/dn-net/test/net.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
IMAGE=${OPENWRT_ROOTFS:-openwrt/rootfs:x86-64-24.10.8}
docker run --rm -v "$root:/t:ro" "$IMAGE" /bin/sh /t/feed/dn-net/test/in-openwrt.sh
