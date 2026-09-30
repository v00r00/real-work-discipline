#!/usr/bin/env bash
# watch-loop.sh <name> — the watchdog for a command started by run-watched.sh. Prints ONLY events:
#   ⚠️ after WATCH_STALL_SEC (default 120) with no output and no CPU: "check by hand" + a snapshot,
#      repeated every WATCH_STALL_SEC while the silence lasts;
#   ✅ "alive again" once work resumes after an alarm;
#   🏁 "FINISHED, exit N" at the end (and exits).
#
# Sign of life = the output grew OR CPU time grew (≥ 1 s per step). CPU is counted for:
#   · every process in the command's session;
#   · for commands mentioning `gradle`: the Gradle/Kotlin daemons and Gradle test workers, which
#     live outside the session — otherwise a long silent test phase would read as a hang;
#   · for commands mentioning `docker`: BuildKit build steps, which run in cgroups named
#     `system.slice:docker:<id>` (running containers use `docker-<id>.scope` and are NOT counted,
#     so a busy stack next door cannot make a hung build look alive).
# The machine's load average is NOT a sign of life: other services produce it.
#
# Traps found while testing this (each one produced a wrong verdict):
#   · daemons counted for every task → a build next door "revived" a hung `sleep`;
#   · `ps` TRUNCATES the cgroup column unless it is the last one → build steps went uncounted and
#     a busy silent `docker build -q` raised a false alarm;
#   · searching processes by name matches the searching command itself → name patterns below are
#     glued from pieces.
# Blind spots: layer export/push (work inside dockerd itself) and build steps of SOMEONE ELSE'S
# docker build running at the same time (e.g. a CI runner on the same host).
set -uo pipefail
NAME="${1:?task name}"
D="${WATCH_DIR:-/tmp/watched}/$NAME"
STALL="${WATCH_STALL_SEC:-120}"
STEP="${WATCH_STEP_SEC:-15}"
[ -f "$D/pid" ] || { echo "⛔ watch-loop: no task $NAME ($D/pid)"; exit 2; }
PID=$(cat "$D/pid")
DAEMONS=0; grep -q 'gradle' "$D/cmd" 2>/dev/null && DAEMONS=1
DOCKER=0; grep -q 'docker' "$D/cmd" 2>/dev/null && DOCKER=1

cpu() {
  local base bk=0
  base=$(ps -eo sid=,times=,args= | awk -v s="$PID" -v dm="$DAEMONS" '
    BEGIN { g = "Gradle" "Daemon"; k1 = "Kotlin" "CompileDaemon"; k2 = "kotlin-" "daemon"; k3 = "kotlin-compiler-" "embeddable"; w = "Gradle" "WorkerMain" }
    $1 == s || (dm == 1 && (index($0, g) || index($0, k1) || index($0, k2) || index($0, k3) || index($0, w))) { t += $2 }
    END { print t + 0 }')
  if [ "$DOCKER" = 1 ]; then  # cgroup must be the LAST column, or ps truncates it
    bk=$(ps -eo times=,cgroup= | awk 'BEGIN { m = "system.slice:" "docker:" } index($2, m) { t += $1 } END { print t + 0 }')
  fi
  echo $((base + bk))
}
diag() {
  local la mem last
  la=$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)
  mem=$(awk '/MemAvailable/ {printf "%.1f GB", $2/1048576}' /proc/meminfo 2>/dev/null)
  last=$(tail -c 2000 "$D/log" 2>/dev/null | tr '\r' '\n' | grep -v '^\s*$' | tail -1 | cut -c1-160)
  echo "load $la · free $mem · last line: ${last:-(no output)}"
}

last_size=-1; last_cpu=-1; quiet=0; since_alarm=0; alarmed=0
while :; do
  if [ -f "$D/rc" ]; then
    rc=$(cat "$D/rc"); el=$(( $(date +%s) - $(cat "$D/started" 2>/dev/null || date +%s) ))
    tail_=$(tail -c 3000 "$D/log" 2>/dev/null | grep -v '^\s*$' | tail -2 | cut -c1-160 | tr '\n' ' ')
    [ "$rc" = 0 ] && m="🏁 $NAME FINISHED, exit 0" || m="🏁❌ $NAME FINISHED, exit $rc"
    echo "$m (${el} s) · $tail_"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    sleep 2; [ -f "$D/rc" ] && continue
    echo "❌ $NAME: process $PID is gone without an exit code (killed?) · $(diag)"; exit 1
  fi
  size=$(stat -c %s "$D/log" 2>/dev/null || echo 0)
  c=$(cpu)
  active=0
  [ "$size" != "$last_size" ] && active=1
  awk -v a="$c" -v b="$last_cpu" 'BEGIN { exit !(b < 0 || a - b >= 1) }' && active=1
  if [ "$active" = 1 ]; then
    [ "$alarmed" = 1 ] && echo "✅ $NAME is alive again after ${quiet} s of silence"
    quiet=0; since_alarm=0; alarmed=0
  else
    quiet=$((quiet + STEP)); since_alarm=$((since_alarm + STEP))
    if [ "$since_alarm" -ge "$STALL" ]; then
      echo "⚠️ $NAME: ${quiet} s with no output and no CPU — check by hand · $(diag)"
      alarmed=1; since_alarm=0
    fi
  fi
  last_size=$size; last_cpu=$c
  sleep "$STEP"
done
