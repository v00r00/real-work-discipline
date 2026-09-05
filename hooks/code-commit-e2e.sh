#!/bin/sh
# PreToolUse hook on Bash. On `git commit` with staged code files, checks the
# commit message for evidence that the change was run — not just compiled.
#
# WHY. "It compiles and the unit tests are green" is the most common definition
# of done, and it is the one that ships broken software: unit tests exercise the
# code you wrote against the assumptions you made. Something has to run the real
# thing against the real dependency.
#
# Warns, never blocks. Docs-only and refactor-only commits are ignored.

set -e

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# --amend without -m opens an editor; the message is not in the command.
case "$cmd" in
  *"--amend"*)
    case "$cmd" in
      *-m*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

staged=$(cd "$(printf '%s' "$input" | jq -r '.cwd // "."' )" 2>/dev/null && git diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$staged" ] && exit 0

code_files=$(printf '%s' "$staged" | grep -E '\.(rs|java|py|ts|tsx|kt|kts|go|rb|swift|cpp|cc|c|h|hpp|cs|php|scala|clj|ex|exs|erl|hs|ml|dart|js|jsx|mjs|cjs|sh|bash|zsh|fish|sql|graphql|proto)$' || true)
[ -z "$code_files" ] && exit 0

msg=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$msg" ]; then
  msg=$(printf '%s' "$cmd" | sed -n "s/.*-m[[:space:]]*'\([^']*\)'.*/\1/p")
fi
# Heredoc-style message: search the whole command.
case "$cmd" in
  *"<<'EOF'"*|*'<<"EOF"'*|*"<< EOF"*) msg="$cmd" ;;
esac

if printf '%s' "$msg" | grep -qiE 'smoke|curl|psql|docker[[:space:]]?(exec|run|compose)|verified|manual[[:space:]]?(test|smoke)|reality[[:space:]]?check|E2E|end[-[:space:]]?to[-[:space:]]?end|against[[:space:]]+(a[[:space:]]+)?running|live[[:space:]]?stack'; then
  exit 0
fi

ctx=$(printf '[pre-commit reality check]\nYou are committing code (%s):\n%s\n\nThe commit message carries no sign the change was executed (smoke / curl / psql / docker / verified / manual test / E2E / against a running stack).\n\nDone = "verified end to end in <environment>", not "the tests are green".\nCheapest sufficient proof, pick what fits:\n  curl against the running binary\n  psql / a client query to confirm the state actually changed\n  docker exec / docker compose for anything with infrastructure\n\nAlready verified? Put the marker in the message ("verified against running stack").\nDocs- or refactor-only with no runtime effect? Ignore this.' "$(printf '%s' "$code_files" | wc -l | tr -d ' ') file(s)" "$(printf '%s' "$code_files" | head -3)")

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
