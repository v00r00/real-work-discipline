#!/bin/sh
# PreToolUse hook on Edit | Write. block-bad-commands.sh protects the guard files
# from the shell; this one protects them from the editor.
#
# GRANT MECHANISM, same shape as block-test-edits.sh:
#   touch "$HOME/.claude/guard-edit-grants/<sha256-of-absolute-path>"
# Single-shot: consumed by one successful edit. The USER creates it. The
# assistant cannot create one for itself — through the shell that runs into
# rule 5 of block-bad-commands.sh.
#
# Protected by default: this kit's own hooks and settings, and any repository's
# git hooks. Add your own — the check scripts, the evidence recorders, anything
# whose silence would look like a clean result — one glob per line in:
#   $CLAUDE_DIR/discipline/guard-edit-paths.txt

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0

is_guard=0
case "$file" in
  "$CLAUDE_DIR"/hooks/*)       is_guard=1 ;;
  "$CLAUDE_DIR"/settings.json) is_guard=1 ;;
  */.githooks/*)               is_guard=1 ;;
  */.git/hooks/*)              is_guard=1 ;;
esac

extra_file="$CLAUDE_DIR/discipline/guard-edit-paths.txt"
if [ "$is_guard" -eq 0 ] && [ -f "$extra_file" ]; then
  while IFS= read -r pattern; do
    case "$pattern" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254
    case "$file" in $pattern) is_guard=1; break ;; esac
  done < "$extra_file"
fi

[ "$is_guard" -eq 0 ] && exit 0

# Duplicated from block-test-edits.sh on purpose — see the note there.
hash_path() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
  fi
}

grant_dir="$CLAUDE_DIR/guard-edit-grants"
grant_sha=$(hash_path "$file")
grant_file="$grant_dir/$grant_sha"

if [ -z "$grant_sha" ]; then
  jq -n --arg reason "BLOCKED: cannot hash the file path — no sha256sum, shasum or openssl on this machine. Install one of them, or remove this hook from settings.json. Refusing to continue: without a hash every guard file would share one grant." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

if [ -f "$grant_file" ]; then
  rm -f "$grant_file"
  exit 0
fi

reason="BLOCKED: editing a protection file requires an explicit grant from the user.

File: $file

Why. A mechanism the checker can edit itself stops being a check: weaken the
condition 'just this once' and the protection disappears silently. That exact
degeneration has already happened — a convergence check lived outside version
control for three days while the documents claimed the check existed.

If the edit is genuinely needed, tell the user the file and the reason. They
grant it with:
  touch \"$grant_file\"

The grant is single-shot: it disappears after one edit."

jq -n --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
