#!/usr/bin/env bash
# PreToolUse(Bash): a long command may not be sent to the background WITHOUT a watchdog.
# Long work goes through Monitor + ~/.claude/tools/run-watched.sh, which reports
# "check by hand" after 2 minutes with no output and no CPU (see tools/watch-loop.sh).
#
# Why: a background build sat "running" for 25 minutes while doing nothing; nobody knew until a
# human asked. A rule in CLAUDE.md is forgotten at exactly that moment — this hook is its guard.
#
# Let through: a foreground call; anything started via run-watched.sh / watch-loop.sh; a pure
# wait loop (`until …; do sleep …; done`, `while …; do sleep …; done`) — it does no work itself.
input=$(cat)
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false')
[ "$bg" = "true" ] || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
case "$cmd" in
  *run-watched.sh*|*watch-loop.sh*) exit 0 ;;
esac
if printf '%s' "$cmd" | grep -qE '^[[:space:]]*(until|while)[[:space:]]' && printf '%s' "$cmd" | grep -q 'sleep'; then
  exit 0
fi
reason="BLOCKED: run long background work UNDER THE WATCHDOG, not with Bash run_in_background.

Instead:
  Monitor(command: \"~/.claude/tools/run-watched.sh <name> -- <command>\", timeout_ms: 1800000,
          description: \"<what is running>\")
You get \"⚠️ … check by hand\" after 2 minutes with no output and no CPU, \"✅ alive again\",
and \"🏁 FINISHED, exit N\". When the Monitor expires (30 min) the command keeps running — re-arm:
  Monitor(command: \"~/.claude/tools/watch-loop.sh <name>\", timeout_ms: 1800000, …)
Output: /tmp/watched/<name>/log, exit code: /tmp/watched/<name>/rc.

Allowed without a watchdog: wait loops like  until …; do sleep …; done"
jq -n --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
