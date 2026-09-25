#!/bin/sh
# Run the GL.iNet reader (handoff/read-glinet.sh) inside OpenWrt's own userland against GL-style configs, then the
# renderer on what it wrote: both sides of the handoff, end to end.
#   usage: sh handoff/test/read.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
IMAGE=${OPENWRT_ROOTFS:-openwrt/rootfs:x86-64-24.10.8}
docker run --rm -v "$root:/t:ro" "$IMAGE" /bin/sh /t/handoff/test/read-in-openwrt.sh
