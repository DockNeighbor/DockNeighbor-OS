#!/bin/sh
# Run the status page's CGI inside OpenWrt's own userland (jshn, jsonfilter, uci): see in-openwrt.sh.
#   usage: sh feed/dn-status/test/status.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
docker run --rm -v "$root:/t:ro" "${OPENWRT_ROOTFS:-openwrt/rootfs:x86-64-24.10.8}" /bin/sh /t/feed/dn-status/test/in-openwrt.sh
