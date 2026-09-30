#!/usr/bin/env bash
# PreToolUse(Bash): REFUSES git commands that move a branch while a recorded verification run is
# in progress against the same repository.
#
# Why: a run recorder can check the head before and after a run and reject the report if it moved
# — but it can only NOTICE afterwards. An hour-and-a-half run was lost that way: a document was
# committed into the branch under test mid-run. "Verify on a frozen head, write docs after" was a
# rule without a guard; this file is its guard.
#
# "Moving a branch": commit, merge, rebase, reset, checkout, switch, pull, cherry-pick, revert, am,
# stash. Reading (status, log, diff, show, fetch) and push do not move the local head.
#
# Configure:
#   E2E_RUNNER_PATTERN  regex matching the recorder's command line (default: e2e-run\.sh <id>)
#   E2E_DEFAULT_REPO    repository assumed when the run has no --repo (default: none)
# The run's repository is taken from `--repo <path>` in its command line. Paths are resolved to
# the repository root with realpath, so a symlinked checkout is recognised. The command's target
# comes from `cd <dir>` / `git -C <dir>`, otherwise from the hook's cwd.
set -u
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cmd" ] && exit 0
PATTERN="${E2E_RUNNER_PATTERN:-e2e-run\.sh [^-]}"

# 1. Is there a branch-moving git in the command?
printf '%s' "$cmd" | grep -qE '(^|[;&|(]|\s)git(\s+-C\s+\S+)?\s+(commit|merge|rebase|reset|checkout|switch|pull|cherry-pick|revert|am|stash)\b' || exit 0

# 2. Live recorder runs and their repositories.
toplevel() { # path → repository root (realpath) or empty
  local p; p=$(realpath -m "$1" 2>/dev/null) || return 0
  while [ -n "$p" ] && [ ! -e "$p" ]; do p=$(dirname "$p"); done
  [ -d "$p" ] || p=$(dirname "$p")
  git -C "$p" rev-parse --show-toplevel 2>/dev/null | xargs -r realpath 2>/dev/null
}
running=""
while IFS= read -r line; do
  repo=$(printf '%s' "$line" | sed -nE 's/.*--repo[ =]+([^ ]+).*/\1/p')
  [ -z "$repo" ] && repo="${E2E_DEFAULT_REPO:-}"
  [ -z "$repo" ] && continue
  top=$(toplevel "$repo"); [ -n "$top" ] && running="$running $top"
done < <(ps -eo args= | grep -E "$PATTERN" | grep -vE '^(grep|ugrep) ')
[ -z "$running" ] && exit 0

# 3. What the command targets.
targets=""
while IFS= read -r p; do
  [ -n "$p" ] && { t=$(toplevel "$p"); [ -n "$t" ] && targets="$targets $t"; }
done < <(printf '%s' "$cmd" | grep -oE '(\bcd\s+|git\s+-C\s+)[^ ;&|)]+' | sed -E 's/^(cd|git\s+-C)\s+//')
if [ -z "$targets" ] && [ -n "$cwd" ]; then
  t=$(toplevel "$cwd"); [ -n "$t" ] && targets="$t"
fi

for t in $targets; do
  for r in $running; do
    if [ "$t" = "$r" ]; then
      reason="BLOCKED: a recorded verification run is in progress against $r. This git command would move the branch and the recorder would reject the report (verify on a frozen head; write docs after). Wait for the run to finish, or ask the user whether to stop it."
      jq -n --arg reason "$reason" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
      exit 0
    fi
  done
done
exit 0
