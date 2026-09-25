#!/bin/sh
# Run dn-net inside OpenWrt's own userland (uci, jshn, jsonfilter, busybox passwd): see in-openwrt.sh.
#   usage: sh feed/dn-net/test/net.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
IMAGE=${OPENWRT_ROOTFS:-openwrt/rootfs:x86-64-24.10.8}
# dn-auth's verify-root, built static against musl (OpenWrt's libc), for the admin-password cases.
bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
docker run --rm -v "$root:/t:ro" -v "$bin:/out" "${ALPINE:-alpine:3.20}" /bin/sh -c \
  'apk add -q --no-cache gcc musl-dev >/dev/null && gcc -Wall -Werror -static -o /out/verify-root /t/feed/dn-auth/src/verify-root.c -lcrypt'
docker run --rm -v "$root:/t:ro" -v "$bin:/dnauth:ro" "$IMAGE" /bin/sh /t/feed/dn-net/test/in-openwrt.sh
