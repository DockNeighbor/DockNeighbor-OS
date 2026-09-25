#!/bin/sh
# verify-root against a real musl crypt(3) (OpenWrt's libc) with hashes of every kind a router can hold.
#   usage: sh feed/dn-auth/test/auth.test.sh          (needs docker)
set -eu
root=$(cd "$(dirname "$0")/../../.." && pwd)
docker run --rm -v "$root:/t:ro" "${ALPINE:-alpine:3.20}" /bin/sh -c '
set -u
apk add -q --no-cache gcc musl-dev >/dev/null
gcc -Wall -Werror -static -o /usr/local/bin/verify-root /t/feed/dn-auth/src/verify-root.c -lcrypt || exit 1
fails=0
v() { printf "%s" "$2" | verify-root; eq "$1" "$?" "$3"; }
eq() { [ "$2" = "$3" ] && echo "  ok    $1" || { echo "  FAIL  $1: expected $3, got $2"; fails=$((fails + 1)); }; }
shadow() { printf "daemon:*:0:0:99999:7:::\nroot:%s:19000:0:99999:7:::\nnobody:*:0:0:99999:7:::\n" "$1" > /etc/shadow; }
for m in md5 sha256 sha512; do
	shadow "$(mkpasswd -m $m "s3cret pass")"
	echo "$m:"
	v "right password"                 "s3cret pass"   0
	v "right password, trailing newline" "s3cret pass
" 0
	v "wrong password"                 "s3cret pas"    1
	v "trailing space is significant"  "s3cret pass "  1
	v "empty password"                 ""              1
done
echo "no password set:"
shadow ""
v "empty matches an empty hash"        ""              0
v "anything else does not"             "x"             1
echo "locked:"
shadow "!$(mkpasswd -m sha256 pw)"
v "locked entry matches nothing, not even its password" "pw" 1
shadow "*"
v "* matches nothing" "*" 1
echo "cannot tell:"
printf "daemon:*:0:0:99999:7:::\n" > /etc/shadow
v "no root entry"                      "pw"            2
rm /etc/shadow
v "no shadow file"                     "pw"            2
shadow "$(mkpasswd -m sha256 pw)"
v "longer than 128 bytes"              "$(head -c 129 /dev/zero | tr "\0" a)" 2
eq "a NUL inside" "$(printf "pw\000x" | verify-root; echo $?)" 2
eq "128 bytes is allowed (wrong, but judged)" "$(printf "%s" "$(head -c 128 /dev/zero | tr "\0" a)" | verify-root; echo $?)" 1
[ "$fails" -eq 0 ] || { echo "auth.test: $fails failure(s)"; exit 1; }
echo "auth.test: all cases pass"
'
