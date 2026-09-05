#!/bin/sh
# UserPromptSubmit hook. On the first turn and every 20th after that, re-injects
# the section headers of the universal CLAUDE.md and of the project CLAUDE.md.
#
# WHY. Instructions loaded once at session start fade: by turn 20 the model is
# reasoning from the middle of a long context and the rules at the top have lost
# their weight ("lost in the middle"). A header list is cheap and restores the
# map without re-reading whole files.
#
# Counter: /tmp/claude-md-refresh-<session_id>.cnt

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"')
counter_file="/tmp/claude-md-refresh-${session_id}.cnt"

if [ -f "$counter_file" ]; then
  count=$(cat "$counter_file" 2>/dev/null || echo 0)
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$counter_file"

# First turn, then every 20th.
if [ "$count" -ne 1 ] && [ $((count % 20)) -ne 1 ]; then
  exit 0
fi

ctx=""
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  univ=$(grep -E '^##[[:space:]]|^###[[:space:]][0-9]' "$CLAUDE_DIR/CLAUDE.md" | head -10)
  if [ -n "$univ" ]; then
    ctx="$ctx[Universal CLAUDE.md ($CLAUDE_DIR/CLAUDE.md) — refresh turn $count]\n$univ\n\n"
  fi
fi

proj_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$proj_cwd" ] && proj_cwd="$(pwd)"

if [ -f "$proj_cwd/CLAUDE.md" ]; then
  proj=$(grep -E '^##[[:space:]]|^###[[:space:]][0-9]' "$proj_cwd/CLAUDE.md" | head -15)
  if [ -n "$proj" ]; then
    ctx="$ctx[Project CLAUDE.md ($proj_cwd/CLAUDE.md) headers]\n$proj\n"
  fi
fi

[ -z "$ctx" ] && exit 0

ctx="$ctx\nFull files: $CLAUDE_DIR/CLAUDE.md + $proj_cwd/CLAUDE.md — re-read if you need the detail."

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
