#!/bin/sh
# Stop hook. Runs your own tracker-consistency check at the end of a turn and
# REPORTS the result. Opt-in: does nothing until you configure it.
#
# INVARIANT: exit 0 always, and blocking here is a regression. The blocking
# version of this hook is the reason the kit exists; the README tells that story.
# Two facts worth keeping close to the code: the Stop event fires after EVERY
# assistant message, not once per session, and the invariant belongs in a
# pre-commit hook, where it stops a bad commit instead of a conversation.
#
# CONFIGURE (all optional; with no config file this hook exits immediately):
#   $CLAUDE_DIR/discipline/tracker.conf
#     WORKSPACE=/absolute/path/to/repo      # only run inside this tree
#     CHECK=/absolute/path/to/check.sh      # your check; exit 0 = converged
#
# Your CHECK script owns the definition of "converged". This hook only runs it,
# and prints its output when it fails. It never blocks: exit 0 always.

set -u

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF="$CLAUDE_DIR/discipline/tracker.conf"

[ -f "$CONF" ] || exit 0

# Parsed, not sourced. Sourcing runs whatever is in the file, and a value with a
# space in it is enough to break it in a way that looks like the hook working.
WORKSPACE=""
CHECK=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  key=${line%%=*}
  val=${line#*=}
  [ "$key" = "$line" ] && continue
  key=$(printf '%s' "$key" | tr -d '[:space:]')
  val=${val#\"}; val=${val%\"}
  case "$key" in
    WORKSPACE) WORKSPACE="$val" ;;
    CHECK)     CHECK="$val" ;;
  esac
done < "$CONF"

[ -n "$CHECK" ] || exit 0
[ -x "$CHECK" ] || exit 0

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

if [ -n "$WORKSPACE" ]; then
  case "$cwd" in
    "$WORKSPACE"|"$WORKSPACE"/*) ;;
    *) exit 0 ;;
  esac
fi

out=$("$CHECK" 2>&1) && exit 0

cat >&2 <<EOF
The findings tracker and the planned work have diverged. The turn is NOT stopped.

$out

Closing this is one line, because a finding has three exits, not two:
  - work to do before release  -> an item in the plan
  - work to do after release   -> an item in the "later" section; the check
                                  counts it as assigned, nothing to schedule
  - not work at all            -> a line in the exclusions block, with the reason

Then bring the totals in the document in line with the facts.

Committing the documents while they diverge will still fail — that invariant
belongs in the pre-commit hook. This is only a notice, so it does not surprise
you later.
EOF
exit 0
