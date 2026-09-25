#!/bin/sh
# Merge every board's dn-* packages (out/hub-lite/<device>/feed/, from scripts/build-hub-lite.sh) into ONE dn_os
# feed in out/hub-lite/feed/, then index and sign it.
#   usage: scripts/publish-feed.sh <secret key file, named *.sec> [public key to verify against]
# One index serves every board: an arch-independent package (Architecture: all) is listed once, and a compiled one
# once per arch; opkg on a router reads only the entries for the archs in its opkg.conf. Every board must have
# been built from the same checkout, so a package has one version across boards.
# Writes Packages, Packages.gz and Packages.sig next to the .ipks; opkg on a router verifies Packages.sig with
# the key in /etc/opkg/keys/1c44072d07e3e228. Publishing (the rolling "feed" release) is the workflow's job, in the
# order packages, then index, then signature.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/scripts/hub-lite-board.sh"
feed="$root/out/hub-lite/feed"; key=$1
pub=${2:-$root/feed/dn-os-upgrade/files/etc/opkg/keys/1c44072d07e3e228}

# Two .ipks carry the same files, contents, modes and control data (their archive timestamps may differ).
same_payload() {
  _t=$(mktemp -d)
  for _i in 1 2; do
    eval "_f=\$$_i"; mkdir -p "$_t/$_i"
    tar -xzf "$_f" -C "$_t/$_i" ./data.tar.gz ./control.tar.gz && mkdir "$_t/$_i/d" "$_t/$_i/c" &&
      tar -xzf "$_t/$_i/data.tar.gz" -C "$_t/$_i/d" && tar -xzf "$_t/$_i/control.tar.gz" -C "$_t/$_i/c" || { rm -rf "$_t"; return 1; }
    (cd "$_t/$_i/d" && find . -exec ls -ld {} + | awk '{print $1, $NF}' | sort) > "$_t/$_i.modes"
    # The SDK stamps each build's time; everything else in control (Depends, scripts) must match.
    sed -i '/^SourceDateEpoch:/d' "$_t/$_i/c/control"
  done
  diff -r "$_t/1/d" "$_t/2/d" >/dev/null && diff -r "$_t/1/c" "$_t/2/c" >/dev/null && cmp -s "$_t/1.modes" "$_t/2.modes"
  _rc=$?; rm -rf "$_t"; return $_rc
}

# Every board of the profile, never a subset: a feed missing a board's arch would strand that board's compiled
# packages at their image versions.
rm -rf "$feed"; mkdir -p "$feed"
for b in $(hub_lite_boards); do
  src="$root/out/hub-lite/$b/feed"
  ls "$src"/*.ipk >/dev/null 2>&1 || { echo "publish-feed: no packages for board $b in $src" >&2; exit 1; }
  for ipk in "$src"/*.ipk; do
    n=$(basename "$ipk")
    # The same file name is the same package, version and arch (an arch-all package from each board): keep one,
    # but only if both boards built the same files. An arch-all package that differs by board is not arch-all.
    if [ -f "$feed/$n" ]; then
      same_payload "$feed/$n" "$ipk" || { echo "publish-feed: $n differs between boards (not arch-independent)" >&2; exit 1; }
    else
      cp "$ipk" "$feed/$n"
    fi
  done
done

# The index opkg reads: one stanza per package, from the control file inside each .ipk (a gzipped tar of
# debian-binary, control.tar.gz, data.tar.gz), plus Filename, Size and SHA256sum.
: > "$feed/Packages"
for ipk in "$feed"/*.ipk; do
  t=$(mktemp -d)
  tar -xzf "$ipk" -C "$t" ./control.tar.gz
  tar -xzf "$t/control.tar.gz" -C "$t" ./control
  { grep -v -e '^Filename:' -e '^Size:' -e '^SHA256sum:' -e '^$' "$t/control"
    echo "Filename: $(basename "$ipk")"
    echo "Size: $(wc -c < "$ipk" | tr -d ' ')"
    echo "SHA256sum: $(sha256sum "$ipk" | cut -d' ' -f1)"
    echo; } >> "$feed/Packages"
  rm -rf "$t"
done

# Each (package, arch) exactly once. Two versions of one package would mean the boards were built from different
# checkouts; an arch-all package listed twice would let opkg pick either.
dups=$(awk '/^Package: /{p=$2} /^Architecture: /{print p " " $2}' "$feed/Packages" | sort | uniq -d)
[ -z "$dups" ] || { echo "publish-feed: listed more than once (package arch): $dups" >&2; exit 1; }
gzip -9nc "$feed/Packages" > "$feed/Packages.gz"
signify-openbsd -S -s "$key" -m "$feed/Packages" -x "$feed/Packages.sig"
signify-openbsd -V -q -p "$pub" -m "$feed/Packages" -x "$feed/Packages.sig" ||
  { echo "publish-feed: the index does not verify against $pub" >&2; exit 1; }
awk '/^Package: /{p=$2} /^Version: /{v=$2} /^Architecture: /{print p "\t" v "\t" $2}' "$feed/Packages"
