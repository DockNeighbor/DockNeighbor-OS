#!/bin/sh
# Build the DockNeighbor OS hub-lite image (GL.iNet GL-MT300N-V2) from pinned upstream OpenWrt artifacts:
# the SDK compiles only what we change (dropbear with Ed25519, dn-handoff), and the ImageBuilder assembles
# the image. No full OpenWrt tree, so this runs on a stock CI runner.
#   usage: scripts/build-hub-lite.sh        (x86-64 Linux; WORK_DIR defaults to ./build/hub-lite)
# Output: out/hub-lite/ — the sysupgrade image, SHA256SUMS and the package manifest. The image is then
# checked by scripts/check-hub-lite-image.sh, which fails the build on any missing guarantee.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
prof="$root/profiles/hub-lite"
. "$prof/upstream.env"
. "$prof/profile.env"
work=${WORK_DIR:-$root/build/hub-lite}; dl=${DL_DIR:-$work/dl}; out="$root/out/hub-lite"
jobs=${JOBS:-$(nproc 2>/dev/null || echo 2)}

missing=""
for t in curl zstd tar make gcc g++ gawk python3 rsync unzip file perl patch bzip2 xz sha256sum unsquashfs signify-openbsd; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
[ -z "$missing" ] || { echo "build: missing host tools:$missing" >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "build: the OpenWrt SDK and ImageBuilder are x86-64 Linux only" >&2; exit 1; }
mkdir -p "$work" "$dl"

# fetch URL FILE SHA256: download once into $dl, and never use a file whose hash doesn't match the pin.
fetch() {
  if ! echo "$3  $dl/$2" | sha256sum -c --status 2>/dev/null; then
    curl -fsSL --retry 3 -o "$dl/$2.part" "$1"
    mv "$dl/$2.part" "$dl/$2"
  fi
  echo "$3  $dl/$2" | sha256sum -c --status || { echo "build: $2 does not match its pinned sha256" >&2; exit 1; }
}

fetch "$OPENWRT_BASE/$SDK_FILE" "$SDK_FILE" "$SDK_SHA256"
fetch "$OPENWRT_BASE/$IB_FILE" "$IB_FILE" "$IB_SHA256"

# The hub-lite, pinned by version and sha256 (upstream.env). The signed index is still read: it must verify, and
# while it lists the pinned version its hash must match the pin. When the Hub has moved on, say so.
curl -fsSL --retry 3 -o "$work/hl.Packages" "$HUB_LITE_FEED/Packages"
curl -fsSL --retry 3 -o "$work/hl.Packages.sig" "$HUB_LITE_FEED/Packages.sig"
signify-openbsd -V -q -p "$prof/keys/$HUB_LITE_FEED_KEY" -x "$work/hl.Packages.sig" -m "$work/hl.Packages" ||
  { echo "build: the hub-lite feed index is not signed by $HUB_LITE_FEED_KEY" >&2; exit 1; }
idx_sha=$(awk -v v="$HUB_LITE_VERSION" '
  /^Package: /{p=$2} /^Version: /{ver=$2} /^SHA256sum: /{s=$2}
  /^$/{ if (p=="brvg-hub-lite" && ver==v) print s; p=ver=s="" }
  END{ if (p=="brvg-hub-lite" && ver==v) print s }' "$work/hl.Packages")
if [ -n "$idx_sha" ]; then
  [ "$idx_sha" = "$HUB_LITE_SHA256" ] ||
    { echo "build: the signed feed says brvg-hub-lite $HUB_LITE_VERSION is $idx_sha, the pin says $HUB_LITE_SHA256" >&2; exit 1; }
else
  echo "::notice::the Hub's hub-lite feed has moved to $(awk '/^Version: /{print $2}' "$work/hl.Packages" | tail -1); this image pins $HUB_LITE_VERSION (profiles/hub-lite/upstream.env)"
fi
hl_ipk="brvg-hub-lite_${HUB_LITE_VERSION}_all.ipk"
fetch "$HUB_LITE_FEED/$hl_ipk" "$hl_ipk" "$HUB_LITE_SHA256"

# --- SDK: dropbear with Ed25519, and every package defined in feed/ -----------------------------------
# Our packages are exactly the ones whose Makefile is in this checkout's feed/, never whatever a reused SDK has
# lying around in bin/.
dn_pkgs=$(sed -n 's/^PKG_NAME:=//p' "$root"/feed/*/Makefile | sort)
[ -n "$dn_pkgs" ] || { echo "build: no packages found in feed/" >&2; exit 1; }
sdk="$work/${SDK_FILE%.tar.zst}"
[ -d "$sdk" ] || tar -I zstd -xf "$dl/$SDK_FILE" -C "$work"
cd "$sdk"
{ grep -v '^src-link dn ' feeds.conf.default; echo "src-link dn $root/feed"; } > feeds.conf
# The base feed is a checkout pinned at the release commit: clone it once, then only re-index (an update on a
# reused SDK tries to `git pull` a detached HEAD and fails). Either way it must sit at the pinned commit.
if [ -d feeds/base/.git ]; then ./scripts/feeds update -i base >/dev/null; else ./scripts/feeds update base >/dev/null; fi
[ "$(git -C feeds/base rev-parse HEAD)" = "$OPENWRT_COMMIT" ] || { echo "build: feeds/base is not at $OPENWRT_COMMIT" >&2; exit 1; }
./scripts/feeds update dn >/dev/null
./scripts/feeds install dropbear $dn_pkgs >/dev/null
# The ImageBuilder must pick OUR dropbear over the identical-version upstream one in its package feed, so ours
# carries a higher release. Reset first: a reused SDK already has the bump.
mk=feeds/base/package/network/services/dropbear/Makefile
git -C feeds/base checkout -q -- package/network/services/dropbear/Makefile
rel=$(sed -n 's/^PKG_RELEASE:=\([0-9][0-9]*\)$/\1/p' "$mk")
[ -n "$rel" ] || { echo "build: can't read dropbear's PKG_RELEASE" >&2; exit 1; }
sed -i "s/^PKG_RELEASE:=$rel\$/PKG_RELEASE:=$((rel + 100))/" "$mk"
{ echo CONFIG_PACKAGE_dropbear=m; echo CONFIG_DROPBEAR_ED25519=y; for p in $dn_pkgs; do echo "CONFIG_PACKAGE_$p=m"; done; } > .config
make defconfig >/dev/null
# dropbear is a target default, so the SDK selects it =y; either way it is built as a package here.
for sym in 'CONFIG_DROPBEAR_ED25519=y' 'CONFIG_PACKAGE_dropbear=[ym]' $(for p in $dn_pkgs; do echo "CONFIG_PACKAGE_$p=[ym]"; done); do
  grep -q "^$sym\$" .config || { echo "build: $sym did not survive defconfig" >&2; exit 1; }
done
rm -rf bin
pkgs="package/dropbear/compile $(for p in $dn_pkgs; do printf 'package/%s/compile ' "$p"; done)"
make -j"$jobs" $pkgs || make -j1 V=s $pkgs
# dropbear, a target default package, lands under bin/targets/; feed packages under bin/packages/.
db_ipk=$(find bin -name "dropbear_*-r$((rel + 100))_*.ipk" | head -1)
[ -n "$db_ipk" ] || { echo "build: the SDK produced no dropbear package" >&2; exit 1; }
# The dn_os feed: exactly one .ipk per package in feed/.
rm -rf "$out-feed"; mkdir -p "$out-feed"
for p in $dn_pkgs; do
  f=$(find bin -name "${p}_*.ipk" | head -1)
  [ -n "$f" ] || { echo "build: the SDK produced no $p package" >&2; exit 1; }
  cp "$f" "$out-feed/"
done

# --- ImageBuilder ---------------------------------------------------------------------------------------
ib="$work/${IB_FILE%.tar.zst}"
[ -d "$ib" ] || tar -I zstd -xf "$dl/$IB_FILE" -C "$work"
cd "$ib"
rm -rf packages/*.ipk bin files
cp "$sdk/$db_ipk" "$out-feed"/*.ipk "$dl/$hl_ipk" packages/
mkdir -p files/etc; [ -d "$prof/files" ] && cp -R "$prof/files/." files/
cat > files/etc/dn-release <<EOF
DN_OS_PROFILE=hub-lite
DN_OS_VERSION=$DN_OS_VERSION
DN_OS_UPSTREAM="OpenWrt $OPENWRT_VERSION $OPENWRT_TARGET"
DN_OS_HUB_LITE=$HUB_LITE_VERSION
DN_OS_CHANNEL_URL=$DN_OS_CHANNEL_URL
EOF
make image PROFILE="$DEVICE" PACKAGES="$PACKAGES" FILES="$ib/files" DISABLED_SERVICES="$DISABLED_SERVICES" \
  EXTRA_IMAGE_NAME="dn-hub-lite-$DN_OS_VERSION"

img=$(ls bin/targets/$OPENWRT_TARGET/*"$DEVICE"-squashfs-sysupgrade.bin 2>/dev/null | head -1)
[ -n "$img" ] || { echo "build: no sysupgrade image produced" >&2; exit 1; }
rm -rf "$out"; mkdir -p "$out"
mv "$out-feed" "$out/feed"
cp "$img" "$out/"
cp bin/targets/$OPENWRT_TARGET/*.manifest "$out/"
sh "$root/scripts/check-hub-lite-image.sh" "$out/$(basename "$img")"
(cd "$out" && sha256sum ./*.bin > SHA256SUMS)
cat "$out/SHA256SUMS"
