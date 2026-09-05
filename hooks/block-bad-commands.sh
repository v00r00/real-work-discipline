#!/bin/sh
# PreToolUse hook on Bash. BLOCKS shortcut commands that are forbidden on paper
# and get run anyway, out of muscle memory.
#
# Blocks:
#   1. staging the whole tree at once (-A, --all, dot) -> name the files
#   2. force push without a lease
#   3. skipping git hooks, long form and short form
#   4. git config core.hooksPath                       -> disarms every git hook at once
#   5. rm/mv/chown/ln/truncate/shred against a guard file
#   6. interactive git (-i)                            -> waits for a terminal nobody is at
#
# Output convention: JSON with permissionDecision=deny, exit 0. The tool call is
# rejected and the model is told why, in the same turn.
#
# Editing this file: several rules match on a literal substring, so writing it
# through a shell heredoc trips its own rules. Use a file tool.

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

# 1. Staging the whole tree at once. Matched only as a real command (start of
# line, or after a shell separator), never as a substring inside an echo. The
# bare-dot form is matched as a whole argument so that staging a dotfile by name
# still works.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]+(&&|\|\||;|\|)[[:space:]]+)git add (-A|--all|\.)([[:space:]]|$)'; then
  deny "Staging the whole tree at once is blocked. It is how a .env, a private key or a debug dump ends up in history — one command, no review. Name the files: git add path/one path/two. If the set really is large, run git status first, read the list, then add explicitly."
fi

# 2. Force push without a lease.
case "$cmd" in
  *"git push --force"*|*"git push -f "*|*"git push -f$"*)
    case "$cmd" in
      *"--force-with-lease"*) ;;
      *)
        deny "Force-pushing without a lease is blocked. --force-with-lease refuses the push if the remote moved since you last fetched — it is the difference between overwriting your own work and overwriting someone else's. Use: git push --force-with-lease origin <branch>. Never force-push a shared branch."
        ;;
    esac
    ;;
esac

# 3. Skipping git hooks, long form.
case "$cmd" in
  *"--no-verify"*)
    deny "Skipping git hooks is blocked without explicit permission from the user. Pre-commit and pre-push hooks are there on purpose. If a hook is in the way, read its message — it usually states the correct path. Override only if the user actually said to skip the hook."
    ;;
esac

# 3a. The SHORT form of the same thing, including clusters such as -nm. Rule 3
# only covered the long form; the short one passed freely until a probe caught it.
#
# Scope is strictly `commit`. On a push, -n means --dry-run — a harmless no-op
# run. Blocking that would be a false positive, and a guard with false positives
# is the first thing anyone works around.
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]]|[;&|][[:space:]]*)git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]+--?[a-zA-Z-]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+-[a-zA-Z]*n'; then
  deny "Committing with -n is the short form of the same hook skip and is blocked the same way. Read the hook's message — it usually states the correct path. Override only if the user actually said to skip the hook."
fi

# 4. core.hooksPath — disarms every git hook at once, and more quietly than the
# per-command flag does.
case "$cmd" in
  *"core.hooksPath"*)
    deny "Repointing core.hooksPath disarms every git hook at once — the same bypass as skipping verification per command, just quieter. If a hook is wrong, read its message and fix the cause, or get explicit permission from the user."
    ;;
esac

# 5. Destroying the guards themselves through the shell.
#
# DIRECTION MATTERS: reading from and backing up a guard path is allowed, writing
# to it is not. Without that distinction you cannot take a snapshot before an
# edit — which is exactly what you should be doing.
#
# Add your own protected paths, one extended-regex alternative per line, in:
#   $CLAUDE_DIR/discipline/guard-paths.txt
esc() { printf '%s' "$1" | sed 's/[].[^$*\/]/\\&/g'; }
GUARD_PATHS="\.git/hooks|\.githooks|$(esc "$CLAUDE_DIR")/hooks|$(esc "$CLAUDE_DIR")/settings\.json"
extra_file="$CLAUDE_DIR/discipline/guard-paths.txt"
if [ -f "$extra_file" ]; then
  extra=$(grep -vE '^[[:space:]]*(#|$)' "$extra_file" | tr '\n' '|' | sed 's/|$//')
  [ -n "$extra" ] && GUARD_PATHS="$GUARD_PATHS|$extra"
fi

# chmod is judged separately: REMOVING the execute bit disarms a guard, ADDING it
# is how a guard gets installed. A rule without that distinction blocks you from
# creating a new hook — found the hard way, on chmod +x of a brand new file.
if printf '%s' "$cmd" | grep -qE "chmod[[:space:]]+[^|;&]*($GUARD_PATHS)"; then
  if printf '%s' "$cmd" | grep -qE 'chmod[[:space:]]+(-[^[:space:]]+[[:space:]]+)*([augo]*-[rwx]|[0-7]?[0-6][0-6][0-6])'; then
    deny "Removing the execute bit from a guard is blocked. Without it the guard does not run, and its silence is indistinguishable from a clean result. Adding permissions (chmod +x, 755) is allowed — that is installing a guard, not disarming one."
  fi
fi

if printf '%s' "$cmd" | grep -qE "(^|[[:space:]]|[;&|][[:space:]]*)(rm|mv|chown|ln|truncate|shred)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^|;&]*($GUARD_PATHS)"; then
  deny "Deleting or renaming a protection file through the shell is blocked. A guard that one command can remove is not a guard — and its absence is invisible: a convergence check once lived outside git for three days while the documents claimed the check existed. Change the contents through Edit with a stated reason; removing protection needs the user's explicit permission."
fi

# 6. Interactive git.
case "$cmd" in
  *"git rebase -i"*|*"git rebase --interactive"*|*"git add -i"*|*"git add --interactive"*)
    deny "Interactive git (-i / --interactive) is blocked — it waits for a terminal that nobody is sitting at, and the call hangs. Use the non-interactive equivalents: git rebase with --exec, or GIT_SEQUENCE_EDITOR with sed, and explicit file names when staging."
    ;;
esac

exit 0
