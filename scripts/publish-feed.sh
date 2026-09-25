#!/bin/sh
# Index and sign the dn_os package feed that scripts/build-hub-lite.sh left in out/hub-lite/feed/.
#   usage: scripts/publish-feed.sh <secret key file, named *.sec> [public key to verify against]
# Writes Packages, Packages.gz and Packages.sig next to the .ipks; opkg on a router verifies Packages.sig with
# the key in /etc/opkg/keys/1c44072d07e3e228. Publishing (the rolling "feed" release) is the workflow's job.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
feed="$root/out/hub-lite/feed"; key=$1
pub=${2:-$root/feed/dn-os-upgrade/files/etc/opkg/keys/1c44072d07e3e228}
ls "$feed"/*.ipk >/dev/null 2>&1 || { echo "publish-feed: no packages in $feed" >&2; exit 1; }

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
gzip -9nc "$feed/Packages" > "$feed/Packages.gz"
signify-openbsd -S -s "$key" -m "$feed/Packages" -x "$feed/Packages.sig"
signify-openbsd -V -q -p "$pub" -m "$feed/Packages" -x "$feed/Packages.sig" ||
  { echo "publish-feed: the index does not verify against $pub" >&2; exit 1; }
grep -E '^(Package|Version):' "$feed/Packages" | paste - -
