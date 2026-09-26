#!/bin/sh
# Does the hub-lite restore actually STOP, and does it stop pulling the package index?
#   usage: sh feed/dn-hub-lite-os/test/restore.test.sh
#
# 🔴 THIS TEST IS A DATA BILL, NOT A CODE PATH. The bug it guards was not a wrong answer — the script
# did exactly what it said — it was an unbounded loop that ran a full `opkg update` every five
# minutes for ever on a router whose wanted hub-lite could never be installed. So the assertions
# here are COUNTS: how many index fetches, how many attempts, and does it ever end.
#
# `opkg`, `logger` and `date` are stubs on PATH. The clock is a file, so a five-day retry ladder runs
# in milliseconds and the index-freshness window can be crossed on purpose.
set -eu

root=$(cd "$(dirname "$0")/../../.." && pwd)
RESTORE="$root/feed/dn-hub-lite-os/files/usr/libexec/dn-hub-lite/restore"
[ -f "$RESTORE" ] || { echo "🟡 UNVERIFIABLE: no $RESTORE"; exit 2; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
pass() { echo "  ok    $*"; }
bad() { echo "  FAIL  $*"; fails=$((fails + 1)); }
eq() { [ "$2" = "$3" ] && pass "$1" || bad "$1: expected '$3', got '$2'"; }

mkdir -p "$W/bin"
cat > "$W/bin/date" <<'EOF'
#!/bin/sh
[ "$1" = "+%s" ] && { cat "$FAKE_NOW"; exit 0; }
exec /bin/date "$@"
EOF
# The opkg stub: records every call, answers `status` from a file the test sets, and decides whether
# an install actually lands from INSTALLS_OK.
cat > "$W/bin/opkg" <<'EOF'
#!/bin/sh
echo "$1" >> "$OPKG_LOG"
case "$1" in
  update)  [ "$(cat "$UPDATE_OK")" = "1" ] && exit 0 || exit 1 ;;
  status)  v=$(cat "$INSTALLED"); [ -n "$v" ] && echo "Version: $v"; exit 0 ;;
  upgrade|install)
    [ "$(cat "$INSTALLS_OK")" = "1" ] && cat "$WANTED" > "$INSTALLED"
    exit 0 ;;
  compare-versions)
    # $2 op $4 — only '>=' is used, and only on plain dotted versions.
    [ "$(printf '%s\n%s\n' "$2" "$4" | sort -V | head -1)" = "$4" ] && exit 0 || exit 1 ;;
esac
exit 0
EOF
cat > "$W/bin/logger" <<'EOF'
#!/bin/sh
shift 2 2>/dev/null || true
echo "$*" >> "$LOGGER_LOG"
EOF
chmod 755 "$W/bin"/*

export FAKE_NOW="$W/now" OPKG_LOG="$W/opkg.log" LOGGER_LOG="$W/logger.log"
export INSTALLED="$W/installed" WANTED="$W/wanted" UPDATE_OK="$W/update_ok" INSTALLS_OK="$W/installs_ok"
export DN_RESTORE_STATE="$W/run" DN_RESTORE_DN_DIR="$W/dn" DN_RESTORE_MIN="$W/dn/hub-lite.min"
export PATH="$W/bin:$PATH"

reset() { # reset <installed> <wanted> <update_ok> <installs_ok>
  rm -rf "$W/run" "$W/dn"; mkdir -p "$W/run" "$W/dn"
  : > "$OPKG_LOG"; : > "$LOGGER_LOG"
  echo 1000000 > "$FAKE_NOW"
  printf '%s' "$1" > "$INSTALLED"; printf '%s' "$2" > "$WANTED"
  echo "$3" > "$UPDATE_OK"; echo "$4" > "$INSTALLS_OK"
  printf '%s' "$2" > "$W/dn/hub-lite.min"
}
run() { sh "$RESTORE"; }                   # caller handles the exit code
rc() { _r=0; sh "$RESTORE" || _r=$?; echo "$_r"; }
updates() { grep -c '^update$' "$OPKG_LOG" 2>/dev/null | head -1; }
# Drive the loop the way the init script does: sleep for whatever restore asked for.
loop() { # loop <max-iterations>
  _i=0
  while [ "$_i" -lt "$1" ]; do
    _i=$((_i + 1))
    if sh "$RESTORE"; then echo "$_i"; return 0; fi
    _w=$(cat "$W/run/dn-hub-lite.restore.wait" 2>/dev/null || echo 300)
    echo $(( $(cat "$FAKE_NOW") + _w )) > "$FAKE_NOW"
  done
  echo "NEVER"
}

echo "dn-hub-lite restore"

# ── the happy paths ──────────────────────────────────────────────────────────────────────────────
reset "" "" 1 1; rm -f "$W/dn/hub-lite.min"
eq "nothing to restore exits 0 at once" "$(rc)" "0"
eq "...and touches the network not at all" "$(updates)" "0"

reset "0.18.9" "0.18.5" 1 1
eq "already newer than wanted: exits 0" "$(rc)" "0"
eq "...without fetching the index" "$(updates)" "0"
[ -f "$W/dn/hub-lite.min" ] && bad "the marker should be cleared" || pass "the marker is cleared"

reset "0.18.4" "0.18.9" 1 1
eq "a restore that works exits 0 first time" "$(rc)" "0"
eq "...having fetched the index once" "$(updates)" "1"
[ -f "$W/dn/hub-lite.min" ] && bad "marker should be cleared on success" || pass "marker cleared on success"

# ── 🔴 THE BUG: reachable feed, unobtainable version ─────────────────────────────────────────────
# The old script ran here for ever at one full index fetch every 5 minutes. 288 a day, on LTE.
reset "0.18.4" "0.18.9" 1 0
t0=$(cat "$FAKE_NOW")
iters=$(loop 500)
t1=$(cat "$FAKE_NOW")
[ "$iters" = "NEVER" ] && bad "IT NEVER STOPS - this is the bug" || pass "it stops, after $iters attempts"
eq "it stops within the retry budget" "$([ "$iters" != "NEVER" ] && [ "$iters" -le 21 ] && echo yes || echo no)" "yes"
# 🔴 THE ASSERTION THAT IS THE WHOLE POINT: the DATA RATE, not a raw count. At the 6 h cap each
# attempt genuinely is 6 h since the last fetch, so it re-checks — that is the only way it could ever
# discover a feed that has since gained the version, and it is the behaviour we want. What must never
# come back is one full index pull per attempt at a flat five minutes.
n=$(updates)
days=$(( (t1 - t0) / 86400 )); [ "$days" -lt 1 ] && days=1
rate=$(( n / days ))
pass "ran $iters attempts over ~${days}d, fetching the index $n time(s)"
[ "$rate" -le 5 ] && pass "index fetches: ~$rate/day (the flat 300 s loop was 288/day, for ever)" \
                  || bad "index fetches: ~$rate/day - the freshness cache is not working"
[ "$n" -lt "$iters" ] && pass "and fewer fetches than attempts, so the cache does bite" \
                      || bad "one index fetch per attempt - the cache is doing nothing"
grep -q "GIVING UP" "$LOGGER_LOG" && pass "it says why it stopped" || bad "no give-up line in the log"
[ -f "$W/dn/hub-lite.restore.giveup" ] && pass "and leaves the marker that answers 'why is this router old'" \
                                       || bad "no give-up marker written"

# Once it has given up it must stay stopped — a re-run must not restart the burn.
before=$(updates)
eq "a later run after giving up exits 0" "$(rc)" "0"
eq "...and fetches nothing more" "$(updates)" "$before"

# ── the cheap failure: feed unreachable ──────────────────────────────────────────────────────────
reset "0.18.4" "0.18.9" 0 0
eq "feed unreachable: non-zero so the loop retries" "$(rc)" "1"
grep -q "feed unreachable" "$LOGGER_LOG" && pass "and says so" || bad "no 'feed unreachable' line"

# ── the backoff ladder ───────────────────────────────────────────────────────────────────────────
reset "0.18.4" "0.18.9" 1 0
run >/dev/null 2>&1 || true
eq "first retry is 10 min (300 doubled)" "$(cat "$W/run/dn-hub-lite.restore.wait")" "600"
run >/dev/null 2>&1 || true
eq "then 20 min" "$(cat "$W/run/dn-hub-lite.restore.wait")" "1200"
reset "0.18.4" "0.18.9" 1 0
_i=0; while [ "$_i" -lt 12 ]; do _i=$((_i+1)); run >/dev/null 2>&1 || true; done
eq "the wait is capped at 6 h" "$(cat "$W/run/dn-hub-lite.restore.wait")" "21600"

# ── somebody fixes it by hand mid-ladder ─────────────────────────────────────────────────────────
reset "0.18.4" "0.18.9" 1 0
run >/dev/null 2>&1 || true; run >/dev/null 2>&1 || true
printf '0.18.9' > "$INSTALLED"
eq "a hand-installed hub-lite ends it" "$(rc)" "0"
[ -f "$W/dn/hub-lite.min" ] && bad "marker should be gone" || pass "marker cleared"

# ── a reboot is a fresh, full-speed attempt ──────────────────────────────────────────────────────
# The backoff lives in tmpfs on purpose: someone may have fixed the feed, or moved the boat into
# signal. This asserts the choice rather than leaving it to a comment.
reset "0.18.4" "0.18.9" 1 0
run >/dev/null 2>&1 || true; run >/dev/null 2>&1 || true
rm -rf "$W/run"                      # what a reboot does to /var/run
run >/dev/null 2>&1 || true
eq "after a reboot the ladder starts again at 10 min" "$(cat "$W/run/dn-hub-lite.restore.wait")" "600"

# ── the init script must honour the script's delay, not a constant ───────────────────────────────
INIT="$root/feed/dn-hub-lite-os/files/etc/init.d/dn-hub-lite-restore"
grep -q 'dn-hub-lite.restore.wait' "$INIT" && pass "the init script sleeps for the delay restore asked for" \
  || bad "the init script still has a hard-coded sleep - the backoff above does nothing in production"

if [ "$fails" -gt 0 ]; then
  echo ""
  echo "$fails case(s) failed."
  exit 1
fi
echo ""
echo "OK - the restore backs off, stops, and stops fetching the index."
exit 0
