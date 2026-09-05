#!/bin/sh
# PreToolUse hook on Write | Edit | NotebookEdit.
# BLOCKS edits to test files unless the user has granted permission for that
# exact file.
#
# Test-file detection, by basename or path:
#   *Test.java | *IT.java | *Tests.java        Java unit / integration
#   test_*.py | *_test.py | conftest.py        pytest
#   *.test.{ts,tsx,js,jsx}                     Jest style
#   *.spec.{ts,tsx,js,jsx}                     Angular / Karma style
#   */src/test/*                               Maven test source root
#   */tests/*.rs                               Rust integration tests
#
# GRANT MECHANISM (single-shot, per file). The USER runs, in their OWN terminal:
#   mkdir -p $HOME/.claude/test-edit-grants
#   touch $HOME/.claude/test-edit-grants/<sha256-of-absolute-path>
# The deny message prints the exact command. After ONE matching edit the grant
# file is consumed.
#
# The assistant cannot create the grant for itself: doing it through the shell
# runs into rule 5 of block-bad-commands.sh.

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0

is_test=0
base=$(basename "$file")
case "$base" in
  *Test.java|*IT.java|*Tests.java) is_test=1 ;;
  *Test.kt|*IT.kt|*Tests.kt) is_test=1 ;;
  test_*.py|*_test.py|conftest.py) is_test=1 ;;
  *.test.ts|*.test.tsx|*.test.js|*.test.jsx) is_test=1 ;;
  *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) is_test=1 ;;
  *_test.go) is_test=1 ;;
esac
case "$file" in
  */src/test/*) is_test=1 ;;
  *"/tests/"*.rs) is_test=1 ;;
esac

[ "$is_test" -eq 0 ] && exit 0

# Deliberately duplicated in block-guard-edits.sh rather than sourced from a
# shared file. A hook that fails to load a library fails silently, and a silent
# guard is the thing this whole repository is about. macOS has shasum, not
# sha256sum; some minimal images have only openssl.
hash_path() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
  fi
}

grant_dir="$CLAUDE_DIR/test-edit-grants"
grant_sha=$(hash_path "$file")
grant_file="$grant_dir/$grant_sha"

# No hashing tool at all: fail closed. An empty hash would collapse every path to
# one grant file, so one permission would unlock every test in the project.
if [ -z "$grant_sha" ]; then
  jq -n --arg reason "BLOCKED: cannot hash the file path — no sha256sum, shasum or openssl on this machine. Install one of them, or remove this hook from settings.json. Refusing to continue: without a hash every file would share one grant." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
fi

if [ -f "$grant_file" ]; then
  rm -f "$grant_file"
  exit 0
fi

deny_reason="BLOCKED: editing a test requires an explicit grant from the user.

File: $file

Why. A red test has two honest outcomes — the test is wrong, or the code is
wrong. Softening the assertion is a third one, always cheaper, and it produces a
green build with no signal left in it.

To proceed, the USER runs this in their OWN terminal (not through the assistant):

  mkdir -p $grant_dir && touch '$grant_file'

The grant is single-shot: it is consumed by one successful edit of this file.

If you believe the test must change because the production contract legitimately
changed — STOP, explain the contract change to the user, and ask. Do not create
the grant yourself."

jq -n --arg reason "$deny_reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
