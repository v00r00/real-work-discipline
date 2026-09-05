#!/usr/bin/env bash
# Exercises every hook with a real event on stdin, and — for the blockers — with a
# NEGATIVE CONTROL: a case that must be allowed through.
#
# A guard that denies everything looks identical to a guard that works. The
# negative controls are the half of this file that actually proves anything.
#
# Usage: HOME=<some test home> ./test/run-hook-tests.sh
# Expects the kit to be installed into $HOME/.claude.

set -uo pipefail

H="$HOME/.claude/hooks"
ok=0; bad=0

# name | expected (deny|allow) | script | json-on-stdin
check() {
  local name="$1" expect="$2" script="$3" json="$4"
  local out rc got
  out=$(printf '%s' "$json" | "$H/$script" 2>&1); rc=$?
  got="allow"
  printf '%s' "$out" | grep -q '"permissionDecision": *"deny"' && got="deny"
  [ "$rc" = "2" ] && got="deny"
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %s\n' "$name"; ok=$((ok+1))
  else
    printf '  FAIL  %s — expected %s, got %s\n' "$name" "$expect" "$got"; bad=$((bad+1))
  fi
}

# name | must the output be non-empty? (yes|no) | script | json
emits() {
  local name="$1" expect="$2" script="$3" json="$4"
  local out got
  out=$(printf '%s' "$json" | "$H/$script" 2>&1)
  [ -n "$out" ] && got="yes" || got="no"
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %s\n' "$name"; ok=$((ok+1))
  else
    printf '  FAIL  %s — expected output:%s, got:%s\n' "$name" "$expect" "$got"; bad=$((bad+1))
  fi
}

HOOKS_DIR="$HOME/.claude/hooks"
NOVERIFY='--no''-verify'
HOOKSPATH='core.hooks''Path'

echo "== block-bad-commands: must DENY =="
check "force push without a lease"  deny block-bad-commands.sh '{"tool_input":{"command":"git push --force origin main"}}'
check "stage the whole tree"        deny block-bad-commands.sh '{"tool_input":{"command":"git add -A"}}'
check "skip hooks, long form"       deny block-bad-commands.sh "{\"tool_input\":{\"command\":\"git commit $NOVERIFY -m x\"}}"
check "skip hooks, short form"      deny block-bad-commands.sh '{"tool_input":{"command":"git commit -nm wip"}}'
check "repoint the git hooks path"  deny block-bad-commands.sh "{\"tool_input\":{\"command\":\"git -c $HOOKSPATH=/dev/null commit -m x\"}}"
check "delete a guard"              deny block-bad-commands.sh "{\"tool_input\":{\"command\":\"rm -f $HOOKS_DIR/block-bad-commands.sh\"}}"
check "disarm a guard with chmod"   deny block-bad-commands.sh "{\"tool_input\":{\"command\":\"chmod -x $HOOKS_DIR/turn-rules.sh\"}}"
check "interactive rebase"          deny block-bad-commands.sh '{"tool_input":{"command":"git rebase -i HEAD~3"}}'

echo "== block-bad-commands: must ALLOW (negative controls) =="
check "force push WITH a lease"     allow block-bad-commands.sh '{"tool_input":{"command":"git push --force-with-lease origin feat"}}'
check "push -n is a dry run"        allow block-bad-commands.sh '{"tool_input":{"command":"git push -n origin main"}}'
check "chmod +x installs a guard"   allow block-bad-commands.sh "{\"tool_input\":{\"command\":\"chmod +x $HOOKS_DIR/new-guard.sh\"}}"
check "backing a guard up"          allow block-bad-commands.sh "{\"tool_input\":{\"command\":\"cp $HOOKS_DIR/turn-rules.sh /tmp/backup.sh\"}}"
check "staging by name"             allow block-bad-commands.sh '{"tool_input":{"command":"git add src/main.rs README.md"}}'
check "staging a dotfile by name"   allow block-bad-commands.sh '{"tool_input":{"command":"git add .gitignore"}}'
check "reading a system file"       allow block-bad-commands.sh '{"tool_input":{"command":"cat /etc/hosts"}}'
# Reading source through the shell used to be blocked. The rule was removed after
# measurement (see the note at the top of block-bad-commands.sh); this case pins
# the removal, so nobody reintroduces it without also reading why it went.
check "reading source in the shell" allow block-bad-commands.sh '{"tool_input":{"command":"cat /home/you/project/src/main.rs"}}'
check "an ordinary build"           allow block-bad-commands.sh '{"tool_input":{"command":"cargo build --release"}}'
check "an ordinary commit"          allow block-bad-commands.sh '{"tool_input":{"command":"git commit -m \"fix: verified against running stack\""}}'

echo "== block-test-edits =="
check "editing a Java test"         deny  block-test-edits.sh '{"tool_input":{"file_path":"/repo/src/test/java/FooTest.java"}}'
check "editing a pytest file"       deny  block-test-edits.sh '{"tool_input":{"file_path":"/repo/tests/test_foo.py"}}'
check "editing production code"     allow block-test-edits.sh '{"tool_input":{"file_path":"/repo/src/main/java/Foo.java"}}'
check "editing a README"            allow block-test-edits.sh '{"tool_input":{"file_path":"/repo/README.md"}}'

echo "== block-guard-edits =="
check "editing a hook"              deny  block-guard-edits.sh "{\"tool_input\":{\"file_path\":\"$HOOKS_DIR/turn-rules.sh\"}}"
check "editing settings.json"       deny  block-guard-edits.sh "{\"tool_input\":{\"file_path\":\"$HOME/.claude/settings.json\"}}"
check "editing a repo git hook"     deny  block-guard-edits.sh '{"tool_input":{"file_path":"/repo/.git/hooks/pre-commit"}}'
check "editing ordinary code"       allow block-guard-edits.sh '{"tool_input":{"file_path":"/repo/src/main.rs"}}'

echo "== agent-prompt-block =="
# Over 500 characters on purpose: below that the soft rules (4, 5, 6) are skipped
# by design, so a short sloppy prompt is allowed through and is NOT a bug.
check "prompt with no schema"       deny  agent-prompt-block.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Please go and look at the authentication module and tell me everything you find about how it works and whether it is correct, including all the files involved, and give me your general impressions of the code quality, and anything else that seems relevant to you as you read through it. Take your time and be thorough about it, there is a lot of ground to cover here and I want a complete picture of the situation before deciding what to do next about the refactor, because the last time we tried this we ended up rewriting half of it twice over and nobody could say afterwards what the actual problem had been in the first place."}}'
check "short sloppy prompt allowed" allow agent-prompt-block.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"look at the auth module and tell me what you think of it"}}'
check "a well-formed prompt"        allow agent-prompt-block.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"Context: I am testing the hypothesis that the session token is validated on every request. I have already read the middleware and confirmed it calls verify(). Scope: only src/auth/, nothing else. final: a table of route, validated (yes/no), evidence line. Out of scope: do not touch src/api/, no web search, do not propose fixes. If you cannot find a route handler, write NOT_FOUND and where you searched - do not guess."}}'
check "exempt built-in agent"       allow agent-prompt-block.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"Explore","prompt":"find the auth module"}}'

echo "== context injectors: must emit =="
emits "turn rules"                  yes turn-rules.sh '{}'

# A positive control for the version snapshot: a directory with a real manifest.
# Without one the hook correctly stays silent, and pointing it at an empty
# directory would test nothing while looking green.
FIXTURE="$(mktemp -d)"
printf '{"name":"fixture","engines":{"node":"22"},"dependencies":{"react":"19.0.0"}}\n' > "$FIXTURE/package.json"
emits "version snapshot, manifest present" yes project-version-snapshot.sh "{\"session_id\":\"t-$$-a\",\"cwd\":\"$FIXTURE\"}"
emits "version snapshot, no manifest"      no  project-version-snapshot.sh "{\"session_id\":\"t-$$-b\",\"cwd\":\"$(mktemp -d)\"}"
rm -rf "$FIXTURE"
emits "agent routing reminder"      yes agent-spec-reminder.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"x"}}'
emits "subagent verify checklist"   yes agent-verify-reminder.sh '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","description":"x"}}'
emits "merge gate"                  yes merge-gate-reminder.sh '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 42 --merge"}}'

echo "== soft warnings: must fire, and must stay quiet otherwise =="
emits "counted claim in a doc"      yes numeric-claim-warn.sh '{"tool_name":"Write","tool_input":{"file_path":"/repo/PLAN.md","content":"We now have 34 tests passing."}}'
emits "doc with no counted claim"   no  numeric-claim-warn.sh '{"tool_name":"Write","tool_input":{"file_path":"/repo/PLAN.md","content":"The plan is to ship it."}}'
emits "launch with env vars"        yes stale-config-warn.sh '{"tool_input":{"command":"DATABASE_URL=postgres://x cargo run"}}'
emits "launch without env vars"     no  stale-config-warn.sh '{"tool_input":{"command":"cargo test"}}'
emits "merge gate stays quiet"      no  merge-gate-reminder.sh '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
emits "tracker notice unconfigured" no  tracker-convergence-notice.sh '{"cwd":"/repo"}'

echo "== hooks that need real files on disk =="

# claude-md-refresh fires on turn 1 and every 20th. The counter is per session id,
# so a fresh id is turn 1.
emits "CLAUDE.md refresh, turn 1"   yes claude-md-refresh.sh "{\"session_id\":\"t-$$-c\",\"cwd\":\"/nonexistent\"}"
printf '2\n' > "/tmp/claude-md-refresh-t-$$-d.cnt"
emits "CLAUDE.md refresh, turn 3"   no  claude-md-refresh.sh "{\"session_id\":\"t-$$-d\",\"cwd\":\"/nonexistent\"}"
rm -f "/tmp/claude-md-refresh-t-$$-c.cnt" "/tmp/claude-md-refresh-t-$$-d.cnt"

TESTFILE="$(mktemp -d)/FooTest.java"
printf 'class FooTest {\n  void t() {\n    try { x(); } catch (Exception e) { }\n  }\n}\n' > "$TESTFILE"
emits "weakened test detected"       yes test-discipline-check.sh "{\"tool_input\":{\"file_path\":\"$TESTFILE\"}}"
printf 'class FooTest {\n  void t() {\n    assertEquals(2, add(1,1));\n  }\n}\n' > "$TESTFILE"
emits "clean test stays quiet"       no  test-discipline-check.sh "{\"tool_input\":{\"file_path\":\"$TESTFILE\"}}"
rm -rf "$(dirname "$TESTFILE")"

# code-commit-e2e reads the staged files of a real repository.
REPO="$(mktemp -d)"
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'fn main() {}\n' > main.rs && git add main.rs ) >/dev/null 2>&1
emits "code commit, no proof it ran" yes code-commit-e2e.sh "{\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"git commit -m \\\"add main\\\"\"}}"
emits "code commit, proof present"   no  code-commit-e2e.sh "{\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"git commit -m \\\"add main, verified against running stack\\\"\"}}"
( cd "$REPO" && git reset -q && printf 'hi\n' > NOTES.md && git add NOTES.md ) >/dev/null 2>&1
emits "docs-only commit stays quiet" no  code-commit-e2e.sh "{\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"git commit -m \\\"notes\\\"\"}}"
rm -rf "$REPO"

echo
printf 'PASS=%d  FAIL=%d\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
