# A local build box for scripts/build-hub-lite.sh, matching CI (ubuntu-24.04 + profiles/hub-lite/build-deps).
#   docker build -t dn-os-builder -f tools/hub-lite-builder.Dockerfile .
#   docker run --rm -v "$PWD:/src" -v dn-os-cache:/cache -e WORK_DIR=/cache/hub-lite dn-os-builder [sh scripts/build-hub-lite.sh <device>]
FROM ubuntu:24.04
COPY profiles/hub-lite/build-deps /tmp/build-deps
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $(cat /tmp/build-deps) ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# ubuntu:24.04 already has the unprivileged user "ubuntu" (uid 1000). OpenWrt refuses to build as root.
USER ubuntu
WORKDIR /src
CMD ["sh", "scripts/build-hub-lite.sh"]
