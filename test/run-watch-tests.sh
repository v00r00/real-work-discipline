#!/usr/bin/env bash
# Exercises the long-run watchdog (tools/run-watched.sh + tools/watch-loop.sh) for real, with a
# short threshold so it takes seconds instead of minutes.
#
#   NEGATIVE CONTROL  — a command that neither prints nor uses the CPU MUST raise the alarm.
#   POSITIVE CONTROL  — a command that prints nothing but keeps a core busy must NOT.
#   DETACHMENT        — killing the watcher must not kill the command.
#
# A watchdog that never fires looks exactly like a watchdog on a healthy run; the negative
# control is the half that proves anything.
#
# Usage: HOME=<some test home> ./test/run-watch-tests.sh   (kit installed into $HOME/.claude)
set -uo pipefail
T="$HOME/.claude/tools"
export WATCH_STALL_SEC=9 WATCH_STEP_SEC=3 WATCH_DIR="$(mktemp -d)"
ok=0; bad=0
pass() { printf '  PASS  %s\n' "$1"; ok=$((ok+1)); }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; bad=$((bad+1)); }

echo "== watchdog: must alarm (hung command) =="
out=$(timeout 60 "$T/run-watched.sh" hung -- sleep 15 2>&1)
printf '%s' "$out" | grep -q 'check by hand' && pass "silent idle command raises the alarm" \
  || fail "silent idle command raises the alarm" "no alarm in: $out"
printf '%s' "$out" | grep -q 'FINISHED, exit 0' && pass "finish is reported with the exit code" \
  || fail "finish is reported with the exit code" "got: $out"

echo "== watchdog: must stay quiet (busy but silent) =="
out=$(timeout 60 "$T/run-watched.sh" busy -- timeout 15 sh -c 'while :; do :; done' 2>&1)
printf '%s' "$out" | grep -q 'check by hand' && fail "busy silent command stays quiet" "false alarm: $out" \
  || pass "busy silent command stays quiet"
printf '%s' "$out" | grep -q 'FINISHED, exit 124' && pass "a failing exit code is reported" \
  || fail "a failing exit code is reported" "got: $out"

echo "== watchdog: the command survives its watcher =="
"$T/run-watched.sh" survivor -- sleep 20 > /dev/null 2>&1 &
W=$!; sleep 2; kill "$W" 2>/dev/null; wait "$W" 2>/dev/null; sleep 1
P=$(cat "$WATCH_DIR/survivor/pid" 2>/dev/null)
if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then pass "command outlives a killed watcher"; kill "$P"
else fail "command outlives a killed watcher" "command died with the watcher"; fi

rm -rf "$WATCH_DIR"
echo
printf 'PASS=%d  FAIL=%d\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
