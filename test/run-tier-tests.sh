#!/usr/bin/env bash
# Exercises tools/audit-tier1.sh and tools/audit-tier2.sh against a fabricated
# pull request: one clean, one carrying every defect the tier is meant to catch.
#
# GitHub is stubbed. The point is the script's logic, and a test that needs a
# live pull request is a test nobody runs twice.
#
# Usage: ./test/run-tier-tests.sh

set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
ok=0; bad=0

pass() { printf '  PASS  %s\n' "$1"; ok=$((ok+1)); }
flunk() { printf '  FAIL  %s — %s\n' "$1" "$2"; bad=$((bad+1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- a real little repository, so check 6 has an object store to resolve against
REPO="$WORK/repo"
mkdir -p "$REPO" && cd "$REPO"
git init -q
git config user.email t@example.com
git config user.name Tester
echo one > a.md && git add a.md && git commit -q -m first
OLD_SHA=$(git rev-parse HEAD)
echo two >> a.md && git add a.md && git commit -q -m second
HEAD_SHA=$(git rev-parse HEAD)
SHORT_OLD=$(printf '%.8s' "$OLD_SHA")

# --- stubbed gh, chosen by PR number
STUB="$WORK/bin"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "repo view") echo "example/repo"; exit 0 ;;
esac
case "$1 $2" in
  "pr view") cat "$FIXTURES/pr-$3.json"; exit 0 ;;
  "pr diff") cat "$FIXTURES/diff-$3"; exit 0 ;;
  "pr list") echo "[]" | jq -r '.[]'; exit 0 ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"
export FIXTURES="$WORK/fx"
mkdir -p "$FIXTURES"

mkjson() { # number body extra-files-json additions
  cat > "$FIXTURES/pr-$1.json" <<EOF
{
  "number": $1,
  "title": "test pull request $1",
  "body": $2,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "reviewDecision": "APPROVED",
  "reviews": [{"submittedAt": "2026-09-05T10:00:00Z"}],
  "commits": [{"committedDate": "2026-09-05T09:00:00Z"}],
  "files": $3,
  "additions": 10,
  "deletions": 0,
  "headRefOid": "$HEAD_SHA",
  "headRefName": "feature",
  "baseRefName": "main"
}
EOF
}

# ---- PR 1: clean -----------------------------------------------------------
mkjson 1 '"Adds a thing.\n\n## Test plan\n- [x] verified by hand"' '[{"path":"src/main.rs","additions":10}]'
cat > "$FIXTURES/diff-1" <<EOF
+++ src/main.rs
+fn main() { println!("hi"); }
EOF

# ---- PR 2: every defect ----------------------------------------------------
mkjson 2 '""' '[{"path":"notes.md","additions":900},{"path":"deploy.pem","additions":3}]'
cat > "$FIXTURES/diff-2" <<EOF
+++ notes.md
+Verified end to end on commit $SHORT_OLD, all good.
+++ config.yaml
+aws_key = AKIAIOSFODNN7EXAMPLE
+api_key: "s3cr3tvalue0123456789abcdef"
EOF

# ---- PR 3: empty diff (the silent-zero trap) -------------------------------
mkjson 3 '"Body here.\n\n## Test plan\n- [x] done"' '[{"path":"x.txt","additions":1}]'
: > "$FIXTURES/diff-3"

run() { "$HERE/tools/audit-tier1.sh" "$1" --repo example/repo 2>&1; }

echo "== tier 1 =="

out=$(run 1); rc=$?
[ $rc -eq 0 ] && pass "clean PR exits 0" || flunk "clean PR exits 0" "rc=$rc"
grep -q "TIER 1 PASSED" <<<"$out" && pass "clean PR reports passed" || flunk "clean PR reports passed" "no PASSED line"
grep -qE '^0 .*positive control.*PASS' <<<"$out" && pass "positive control fires on a real diff" || flunk "positive control" "not PASS"

out=$(run 2); rc=$?
[ $rc -eq 1 ] && pass "dirty PR exits 1" || flunk "dirty PR exits 1" "rc=$rc"
grep -qE '^4 .*secrets.*FAIL' <<<"$out" && pass "catches the planted cloud key" || flunk "secrets" "not flagged"
grep -q "AKIAIOSFODNN7EXAMPLE" <<<"$out" && pass "prints the offending line" || flunk "secret line printed" "absent"
grep -q "deploy.pem" <<<"$out" && pass "flags the .pem by extension" || flunk "suspect file" "absent"
grep -qE '^3 .*description.*FAIL' <<<"$out" && pass "empty body fails" || flunk "empty body" "not FAIL"
grep -qE '^5 .*oversized.*WARN' <<<"$out" && pass "900-line addition warns" || flunk "oversized" "not WARN"
grep -q "$SHORT_OLD" <<<"$out" && pass "names the stale commit reference in the doc" || flunk "stale sha" "not reported"
grep -qE '^6 .*commit refs.*WARN' <<<"$out" && pass "stale commit reference warns" || flunk "stale sha check" "not WARN"

out=$(run 3); rc=$?
[ $rc -eq 1 ] && pass "empty diff exits 1" || flunk "empty diff exits 1" "rc=$rc"
grep -qE '^0 .*positive control.*FAIL' <<<"$out" && pass "empty diff fails the positive control, not silently passes" || flunk "empty diff" "reported clean"

echo
echo "== tier 2 =="

CONF="$WORK/tier2.conf"
out=$("$HERE/tools/audit-tier2.sh" "$HEAD_SHA" --config "$WORK/nonexistent.conf" 2>&1); rc=$?
[ $rc -eq 0 ] && grep -q "SKIPPED" <<<"$out" && pass "no config: skips and says nothing was checked" || flunk "no config" "rc=$rc"
grep -q "This is not a pass" <<<"$out" && pass "no config: refuses to be read as a pass" || flunk "no config wording" "absent"

if command -v docker >/dev/null 2>&1; then
  printf 'CONTAINER=definitely-not-a-real-container-%s\nARTIFACT=/app/x\n' "$$" > "$CONF"
  out=$("$HERE/tools/audit-tier2.sh" "$HEAD_SHA" --config "$CONF" 2>&1); rc=$?
  [ $rc -eq 1 ] && pass "missing container fails" || flunk "missing container" "rc=$rc"
  grep -q "no such container" <<<"$out" && pass "missing container is named as such" || flunk "missing container wording" "absent"

  RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | head -1)
  if [ -n "$RUNNING" ]; then
    printf 'CONTAINER=%s\nARTIFACT=/etc/hostname\nMARKER=zzz-not-present-%s\n' "$RUNNING" "$$" > "$CONF"
    out=$("$HERE/tools/audit-tier2.sh" "$HEAD_SHA" --config "$CONF" 2>&1); rc=$?
    [ $rc -eq 1 ] && pass "live container, absent marker: fails" || flunk "absent marker" "rc=$rc"

    # Take the marker out of the very file the tool will inspect, by the same
    # route the tool uses. Reading it with `docker exec` instead looked fine and
    # silently fed the text of an exec error in as the marker.
    MARKER=""
    if docker cp "$RUNNING:/etc/hostname" "$WORK/hostname" 2>/dev/null; then
      MARKER=$(tr -cd 'A-Za-z0-9' < "$WORK/hostname" | head -c 8)
    fi
    if [ -n "$MARKER" ]; then
      printf 'CONTAINER=%s\nARTIFACT=/etc/hostname\nMARKER=%s\n' "$RUNNING" "$MARKER" > "$CONF"
      out=$("$HERE/tools/audit-tier2.sh" "$HEAD_SHA" --config "$CONF" 2>&1); rc=$?
      [ $rc -eq 0 ] && pass "live container, present marker: passes" || flunk "present marker" "rc=$rc: $out"
    fi
  else
    echo "  ....  no running container; live-artifact cases not exercised"
  fi
else
  echo "  ....  docker absent; container cases not exercised"
fi

echo
printf 'PASS=%d  FAIL=%d\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
