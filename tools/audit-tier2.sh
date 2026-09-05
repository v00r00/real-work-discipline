#!/usr/bin/env bash
# Tier 2 of the pre-merge audit: does the thing that is RUNNING contain the code
# you are about to merge? Seconds, one config file, no project knowledge baked in.
#
#   tools/audit-tier2.sh <head-sha> [--config path]
#
# Default config: ~/.claude/discipline/audit-tier2.conf
# With no config it prints SKIP and exits 0. It never guesses.
#
# WHY THIS TIER EXISTS AT ALL. Documents and artifacts age with every commit,
# and nothing tells you. Three separate audit rounds of one pull request were
# burned on the same class: the image was built two minutes after the first of
# three commits; the end-to-end run was done on the previous commit; a document
# described a method the branch had already deleted. Each was one command away.
#
# CONFIG FORMAT, one KEY=value per line, # for comments:
#
#   CONTAINER=my-service          # running container to inspect
#   ARTIFACT=/app/app.jar         # path INSIDE the container
#   MARKER=                       # string that must appear inside the artifact.
#                                 # Empty means: use the short head SHA.
#   HEALTH_CMD=curl -sf localhost:8080/health    # optional, run on the host
#
# Repeat the CONTAINER/ARTIFACT/MARKER trio with a numeric suffix for several
# services: CONTAINER2=, ARTIFACT2=, MARKER2=.
#
# The artifact is copied OUT and inspected on the host. Runtime images
# deliberately lack the tools you would need to inspect them from inside, and a
# missing tool prints "0 matches", which reads exactly like "the old code is
# gone".

set -uo pipefail

HEAD_SHA="${1:-}"
CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/discipline/audit-tier2.conf"
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONF="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$HEAD_SHA" ]; then
  echo "usage: $(basename "$0") <head-sha> [--config path]" >&2
  exit 2
fi

if [ ! -f "$CONF" ]; then
  echo "TIER 2 SKIPPED: no config at $CONF"
  echo "Nothing was checked. This is not a pass."
  echo "To enable, create that file with CONTAINER=, ARTIFACT= and optionally MARKER=."
  exit 0
fi

command -v docker >/dev/null 2>&1 || { echo "TIER 2 SKIPPED: docker not found. Nothing was checked."; exit 0; }

# The config is PARSED, not sourced. Sourcing runs whatever is in the file: a
# value with a space in it dies with "command not found", and a value with a
# semicolon in it does something worse. Only these keys are read; anything else
# in the file is ignored.
CONTAINER=""; ARTIFACT=""; MARKER=""
CONTAINER2=""; ARTIFACT2=""; MARKER2=""
CONTAINER3=""; ARTIFACT3=""; MARKER3=""
HEALTH_CMD=""

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  val=${line#*=}
  [ "$key" = "$line" ] && continue          # no '=' on the line
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  val=${val#\"}; val=${val%\"}
  val=${val#\'}; val=${val%\'}
  case "$key" in
    CONTAINER|ARTIFACT|MARKER|CONTAINER2|ARTIFACT2|MARKER2|CONTAINER3|ARTIFACT3|MARKER3|HEALTH_CMD)
      printf -v "$key" '%s' "$val" ;;
    *) echo "ignoring unknown key in $CONF: $key" >&2 ;;
  esac
done < "$CONF"

SHORT=$(printf '%.8s' "$HEAD_SHA")
fails=0
row() { printf '%-24s %-6s %s\n' "$1" "$2" "$3"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "TIER 2 — is the running stack built from $SHORT ?"
echo
printf '%-24s %-6s %s\n' 'subject' 'result' 'detail'
printf -- '------------------------ ------ --------------------------------------\n'

check_one() {
  local container="$1" artifact="$2" marker="$3"
  [ -n "$container" ] || return 0

  local status
  status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
  if [ -z "$status" ]; then
    row "$container" "FAIL" "no such container"
    fails=$((fails + 1)); return 0
  fi
  if [ "$status" != "running" ]; then
    row "$container" "FAIL" "container is $status, not running"
    fails=$((fails + 1)); return 0
  fi

  if [ -z "$artifact" ]; then
    row "$container" "SKIP" "running, but no ARTIFACT given — nothing inspected"
    return 0
  fi

  local out="$TMP/$(echo "$container" | tr -c 'A-Za-z0-9_.-' '_')"
  if ! docker cp "$container:$artifact" "$out" 2>/dev/null; then
    row "$container" "FAIL" "cannot copy $artifact out of the container"
    fails=$((fails + 1)); return 0
  fi

  local want="${marker:-$SHORT}"

  # Positive control before believing a zero: the artifact must contain SOMETHING
  # printable. An empty or unreadable file would otherwise report "marker absent"
  # and look like a real finding.
  if ! LC_ALL=C grep -aqE '[[:print:]]{4,}' "$out"; then
    row "$container" "FAIL" "artifact copied but holds no readable strings — cannot conclude anything"
    fails=$((fails + 1)); return 0
  fi

  if LC_ALL=C grep -aqF "$want" "$out"; then
    row "$container" "PASS" "artifact contains '$want'"
  else
    row "$container" "FAIL" "artifact does NOT contain '$want' — it predates this commit"
    fails=$((fails + 1))
  fi
}

check_one "$CONTAINER"  "$ARTIFACT"  "$MARKER"
check_one "$CONTAINER2" "$ARTIFACT2" "$MARKER2"
check_one "$CONTAINER3" "$ARTIFACT3" "$MARKER3"

if [ -n "$HEALTH_CMD" ]; then
  if eval "$HEALTH_CMD" >/dev/null 2>&1; then
    row "health" "PASS" "$HEALTH_CMD"
  else
    row "health" "FAIL" "$HEALTH_CMD returned non-zero"
    fails=$((fails + 1))
  fi
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "TIER 2 FAILED: $fails check(s)."
  echo "Anything you measured against this stack was measured against older code."
  exit 1
fi
echo "TIER 2 PASSED."
exit 0
