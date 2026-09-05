#!/bin/sh
# PreToolUse hook on Edit / Write / Bash. When the text being written (a doc or a
# commit message) contains a counted claim — "17 tests", "4 files", "230 lines" —
# injects a reminder to get the number from the canonical command.
#
# WHY. A number is the cheapest thing to be confidently wrong about. `grep | wc -l`
# counts matching LINES, not occurrences and not tests; a doc that says "34 tests
# pass" outlives the branch where 34 was true. The number is not the problem —
# writing it from memory is.
#
# Warns, never blocks.

set -e

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
content=""
context_label=""

case "$tool" in
  Write)
    file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    case "$file" in
      *.md|*COMMIT_EDITMSG)
        content=$(printf '%s' "$input" | jq -r '.tool_input.content // empty')
        context_label="write to $file"
        ;;
    esac
    ;;
  Edit)
    file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    case "$file" in
      *.md|*COMMIT_EDITMSG)
        content=$(printf '%s' "$input" | jq -r '.tool_input.new_string // empty')
        context_label="edit of $file"
        ;;
    esac
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    case "$cmd" in
      *"git commit"*-m*)
        content=$(printf '%s' "$cmd" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p')
        if [ -z "$content" ]; then
          content=$(printf '%s' "$cmd" | sed -n "s/.*-m[[:space:]]*'\([^']*\)'.*/\1/p")
        fi
        context_label="git commit message"
        ;;
    esac
    ;;
esac

[ -z "$content" ] && exit 0

matches=$(printf '%s' "$content" | grep -ioE '\b[0-9]+[[:space:]]*(test|tests|case|cases|file|files|commit|commits|line|lines|insertion|insertions|deletion|deletions|error|errors|bug|bugs|defect|defects|unit-?test|migration|migrations)\b' | head -5)

[ -z "$matches" ] && exit 0

ctx=$(printf '[numeric-claim warn — %s]\nCounted claims detected:\n%s\n\nGet each number from the canonical command before writing it:\n  tests / cases -> cargo test --list | mvn test | pytest --collect-only\n  files/commits -> git diff --stat | git log --oneline | wc -l\n  lines         -> wc -l <file>   (NOT grep | wc -l — that counts matching lines)\n  insertions    -> git diff --shortstat\n\nAlready verified? Ignore this. The target is the grep-shortcut, not the number.' "$context_label" "$matches")

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'
