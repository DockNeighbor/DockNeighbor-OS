#!/bin/sh
# A change to a dn-* package that doesn't bump its version never reaches a router: opkg only upgrades to a newer
# version. Fail when any feed/<pkg>/ changed since <base> but its PKG_VERSION/PKG_RELEASE did not.
#   usage: scripts/check-feed-versions.sh <base ref>       (CI passes the PR's base)
set -eu
base=$1
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
fails=0
for d in $(git diff --name-only "$base"...HEAD -- feed/ | cut -d/ -f2 | sort -u); do
  mk="feed/$d/Makefile"
  [ -f "$mk" ] || continue                      # a package removed in this change
  git cat-file -e "$base:$mk" 2>/dev/null || { echo "  new    $d"; continue; }   # new packages start anywhere
  ver() { sed -n -e 's/^PKG_VERSION:=//p' -e 's/^PKG_RELEASE:=//p' | tr '\n' '-'; }
  old=$(git show "$base:$mk" | ver); new=$(ver < "$mk")
  if [ "$old" = "$new" ]; then
    echo "  FAIL   $d changed but its version did not ($new): routers would never receive it"; fails=$((fails + 1))
  else
    echo "  ok     $d ${old%-} -> ${new%-}"
  fi
done
[ "$fails" -eq 0 ] || exit 1
echo "check-feed-versions: every changed package bumps its version"
