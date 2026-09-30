#!/usr/bin/env bash
# run-watched.sh — start a long command UNDER A WATCHDOG. Call it INSIDE the Monitor tool:
#
#   Monitor(command: "~/.claude/tools/run-watched.sh <name> -- <command...>", timeout_ms: 1800000)
#
# Every line the watchdog prints arrives as a notification (see watch-loop.sh):
#   ⚠️ "<name>: N s with no output and no CPU — check by hand"  (+ a snapshot of the machine)
#   ✅ "<name> is alive again"  ·  🏁 "<name> FINISHED, exit N"
#
# The command is detached from the watcher (double fork → reparented to init). A Monitor lives at
# most 30 minutes and is killed together with its whole process tree; without the detachment it
# would take the command down with it. Re-arm a watcher on the same command without restarting it:
#
#   Monitor(command: "~/.claude/tools/watch-loop.sh <name>", timeout_ms: 1800000)
#
# Output: $WATCH_DIR/<name>/log, exit code: $WATCH_DIR/<name>/rc (WATCH_DIR defaults to /tmp/watched).
#
# Why: a background build sat "running" for 25 minutes while doing nothing, and nobody knew until
# a human asked how many cores were busy. Hangs have to announce themselves.
set -uo pipefail
NAME="${1:?task name}"; shift
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "⛔ run-watched: no command after --"; exit 2; }
case "$NAME" in *[!A-Za-z0-9._-]*) echo "⛔ run-watched: name may use only letters, digits, . _ -"; exit 2;; esac
D="${WATCH_DIR:-/tmp/watched}/$NAME"
mkdir -p "$D"
if [ -f "$D/pid" ] && kill -0 "$(cat "$D/pid")" 2>/dev/null && [ ! -f "$D/rc" ]; then
  echo "⛔ $NAME is already running (pid $(cat "$D/pid")) — re-arm instead: ~/.claude/tools/watch-loop.sh $NAME"
  exit 2
fi
rm -f "$D/rc" "$D/log" "$D/pid"
printf '%q ' "$@" > "$D/cmd"
date +%s > "$D/started"
# Own session: sid = pid, which is how the watchdog totals the CPU of the whole command.
# The command writes its own pid; the intermediate subshell exits at once.
( setsid bash -c 'd="$1"; cd "$2"; shift 2; echo $$ > "$d/pid"; "$@" > "$d/log" 2>&1; echo $? > "$d/rc"' \
    _ "$D" "$PWD" "$@" < /dev/null > /dev/null 2>&1 & )
for _ in $(seq 1 50); do [ -s "$D/pid" ] && break; sleep 0.1; done
[ -s "$D/pid" ] || { echo "⛔ $NAME: the command did not start (no $D/pid)"; exit 2; }
echo "▶ $NAME started (pid $(cat "$D/pid")); output: $D/log"
exec "$(dirname "$(readlink -f "$0")")/watch-loop.sh" "$NAME"
