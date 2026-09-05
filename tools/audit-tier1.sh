#!/usr/bin/env bash
# Tier 1 of the pre-merge audit: text, git and files. Under a second, no project
# knowledge, no configuration. Run it before anything expensive.
#
#   tools/audit-tier1.sh <PR-number> [--repo owner/name]
#
# Exit 0 if nothing failed, 1 if anything did. WARN does not fail the run.
#
# Needs: git, gh (authenticated), jq. Run it from inside the repository, because
# check 6 resolves commit SHAs against your local object store.
#
# A check that cannot run prints SKIP, never PASS. A tool that reports "no
# matches" because it never executed is the single most expensive failure mode
# in an audit, and it looks exactly like a clean result.

set -uo pipefail

PR=""
REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) PR="$1"; shift ;;
  esac
done

if [ -z "$PR" ]; then
  echo "usage: $(basename "$0") <PR-number> [--repo owner/name]" >&2
  exit 2
fi

for tool in git gh jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 2; }
done

[ -n "$REPO" ] || REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[ -n "$REPO" ] || { echo "cannot determine the repository; pass --repo owner/name" >&2; exit 2; }

fails=0
row() { printf '%-3s %-26s %-6s %s\n' "$1" "$2" "$3" "$4"; }
fail() { fails=$((fails + 1)); row "$1" "$2" "FAIL" "$3"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fetch once, reuse. Two network calls for the whole run.
# ---------------------------------------------------------------------------
PRJSON="$TMP/pr.json"
if ! gh pr view "$PR" --repo "$REPO" --json \
  number,title,body,mergeable,mergeStateStatus,reviewDecision,reviews,commits,files,additions,deletions,headRefOid,headRefName,baseRefName \
  > "$PRJSON" 2>"$TMP/err"; then
  echo "cannot read PR $PR in $REPO:" >&2
  cat "$TMP/err" >&2
  exit 2
fi

DIFF="$TMP/diff"
gh pr diff "$PR" --repo "$REPO" > "$DIFF" 2>/dev/null || : > "$DIFF"

HEAD_SHA=$(jq -r '.headRefOid' "$PRJSON")
TITLE=$(jq -r '.title' "$PRJSON")

echo "PR $REPO#$PR — $TITLE"
echo "base: $(jq -r '.baseRefName' "$PRJSON")  head: $(jq -r '.headRefName' "$PRJSON") ($(printf '%.8s' "$HEAD_SHA"))"
echo
printf '%-3s %-26s %-6s %s\n' '#' 'check' 'result' 'detail'
printf -- '--- -------------------------- ------ ------------------------------\n'

# ---------------------------------------------------------------------------
# 0. Positive control. Prove the scanners in this environment actually match
#    something before believing any of their zeros. Without this, a broken grep,
#    a missing locale or an empty diff all read as "clean".
# ---------------------------------------------------------------------------
probe='AKIAIOSFODNN7EXAMPLE ghp_0123456789012345678901234567890123456'
if printf '%s\n' "+$probe" | grep -qE "^\+.*\bAKIA[0-9A-Z]{16}\b" &&
   printf '%s\n' "+$probe" | grep -qE "^\+.*\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b"; then
  if [ -s "$DIFF" ]; then
    row 0 "positive control" "PASS" "scanners match a planted secret; diff is non-empty"
  else
    fail 0 "positive control" "the diff is EMPTY — every content check below is meaningless"
  fi
else
  fail 0 "positive control" "the secret patterns do not match a known-bad sample here"
fi

# ---------------------------------------------------------------------------
# 1. Mergeable state.
# ---------------------------------------------------------------------------
MERGEABLE=$(jq -r '.mergeable' "$PRJSON")
STATE=$(jq -r '.mergeStateStatus' "$PRJSON")
case "$MERGEABLE/$STATE" in
  CONFLICTING/*) fail 1 "mergeable" "CONFLICTING — rebase first" ;;
  UNKNOWN/*)     row 1 "mergeable" "WARN" "UNKNOWN — GitHub has not computed it; re-run" ;;
  */BEHIND)      row 1 "mergeable" "WARN" "head is behind base" ;;
  */BLOCKED)     fail 1 "mergeable" "BLOCKED — branch protection refuses (see check 2)" ;;
  *)             row 1 "mergeable" "PASS" "$MERGEABLE / $STATE" ;;
esac

# ---------------------------------------------------------------------------
# 2. Review, and whether the reviewed code is still the code.
# ---------------------------------------------------------------------------
DECISION=$(jq -r '.reviewDecision // "NONE"' "$PRJSON")
LAST_REVIEW=$(jq -r '[.reviews[]?.submittedAt] | max // ""' "$PRJSON")
LAST_COMMIT=$(jq -r '[.commits[]?.committedDate] | max // ""' "$PRJSON")
if [ "$DECISION" = "CHANGES_REQUESTED" ]; then
  fail 2 "review" "changes requested and not resolved"
elif [ -n "$LAST_REVIEW" ] && [ -n "$LAST_COMMIT" ] && [ "$LAST_COMMIT" \> "$LAST_REVIEW" ]; then
  row 2 "review" "WARN" "commits landed after the last review; it approved older code"
elif [ "$DECISION" = "APPROVED" ]; then
  row 2 "review" "PASS" "approved"
else
  row 2 "review" "WARN" "no approving review — section D of the skill is mandatory"
fi

# ---------------------------------------------------------------------------
# 3. Description. An empty body on a pull request nobody reviewed means the only
#    record of intent is the diff.
# ---------------------------------------------------------------------------
BODY=$(jq -r '.body // ""' "$PRJSON")
NFILES=$(jq -r '.files | length' "$PRJSON")
if [ -z "$(printf '%s' "$BODY" | tr -d '[:space:]')" ]; then
  fail 3 "description" "body is empty, $NFILES file(s) changed"
elif ! printf '%s' "$BODY" | grep -qiE 'test plan|how (this )?(was|to) (tested|verify)|verified'; then
  row 3 "description" "WARN" "no test plan and no statement of what was verified"
else
  row 3 "description" "PASS" "$(printf '%s' "$BODY" | wc -l | tr -d ' ') lines, $NFILES file(s)"
fi

# ---------------------------------------------------------------------------
# 4. Secrets. Patterns only; every hit is printed for a human to judge.
# ---------------------------------------------------------------------------
sec="$TMP/secrets"
: > "$sec"
grep -iE "^\+.*BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY" "$DIFF" >> "$sec" 2>/dev/null
grep -E  "^\+.*\bAKIA[0-9A-Z]{16}\b" "$DIFF" >> "$sec" 2>/dev/null
grep -E  "^\+.*\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b" "$DIFF" >> "$sec" 2>/dev/null
grep -E  "^\+.*\bxox[bpoa]-[A-Za-z0-9-]{10,}\b" "$DIFF" >> "$sec" 2>/dev/null
grep -E  "^\+.*eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}" "$DIFF" >> "$sec" 2>/dev/null
grep -iE "^\+.*(api[_-]?key|secret|token|password|passwd|credential)[\"']?[ ]*[:=][ ]*[\"'][a-zA-Z0-9_/+=-]{20,}" "$DIFF" 2>/dev/null \
  | grep -vE "CHANGE_ME|XXXX|<.+>|\\\$\{|\\\$[A-Z_]+|placeholder|example|EXAMPLE|REPLACE|dummy|fake" >> "$sec"

SUSPECT=$(jq -r '.files[].path' "$PRJSON" | grep -iE "\.(key|pem|crt|p12|pfx|env|envrc)$|(^|/)\.env(\.|$)" | head -5)

if [ -s "$sec" ] || [ -n "$SUSPECT" ]; then
  n=$(wc -l < "$sec" | tr -d ' ')
  fail 4 "secrets" "$n diff hit(s), $(printf '%s' "$SUSPECT" | grep -c . ) suspect file(s) — listed below"
else
  row 4 "secrets" "PASS" "no hits"
fi

# ---------------------------------------------------------------------------
# 5. Oversized additions. A large unreferenced text file is usually a debug dump
#    somebody pasted in.
# ---------------------------------------------------------------------------
BIG=$(jq -r '.files[] | select(.additions > 500) | "\(.additions)+ \(.path)"' "$PRJSON")
if [ -n "$BIG" ]; then
  row 5 "oversized files" "WARN" "$(printf '%s' "$BIG" | grep -c .) file(s) over 500 added lines — listed below"
else
  row 5 "oversized files" "PASS" "none over 500 added lines"
fi

# ---------------------------------------------------------------------------
# 6. Stale commit references in changed documents.
#
#    This is the check that pays for the whole script. A document that says
#    "verified on <sha>" ages the moment the next commit lands, and nothing in
#    CI notices. Every SHA-looking token added to a text file is resolved
#    against the local object store and compared to the head of this PR.
# ---------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  awk '/^\+\+\+ /{f=$2} /^\+[^+]/{if (f ~ /\.(md|txt|rst|adoc)$/) print}' "$DIFF" \
    | grep -oE '\b[0-9a-f]{7,40}\b' | sort -u > "$TMP/shas"
  stale=""
  checked=0
  while read -r sha; do
    [ -n "$sha" ] || continue
    git cat-file -e "${sha}^{commit}" 2>/dev/null || continue
    checked=$((checked + 1))
    full=$(git rev-parse "${sha}^{commit}" 2>/dev/null)
    [ "$full" = "$HEAD_SHA" ] && continue
    stale="$stale $sha"
  done < "$TMP/shas"

  if [ -n "$stale" ]; then
    row 6 "commit refs in docs" "WARN" "not the head:$stale"
  elif [ "$checked" -gt 0 ]; then
    row 6 "commit refs in docs" "PASS" "$checked reference(s), all resolve to the head"
  else
    row 6 "commit refs in docs" "PASS" "no commit references in changed documents"
  fi
else
  row 6 "commit refs in docs" "SKIP" "not inside a git repository"
fi

# ---------------------------------------------------------------------------
# 7. Does this branch swallow another open pull request?
# ---------------------------------------------------------------------------
HEAD_REF=$(jq -r '.headRefName' "$PRJSON")
if git rev-parse --git-dir >/dev/null 2>&1 && git fetch -q origin 2>/dev/null; then
  contained=""
  while read -r other; do
    [ -n "$other" ] && [ "$other" != "$HEAD_REF" ] || continue
    git merge-base --is-ancestor "origin/$other" "origin/$HEAD_REF" 2>/dev/null && contained="$contained $other"
  done < <(gh pr list --repo "$REPO" --state open --json headRefName --jq '.[].headRefName' 2>/dev/null)
  if [ -n "$contained" ]; then
    row 7 "branch dependency" "WARN" "merging closes:$contained"
  else
    row 7 "branch dependency" "PASS" "no other open branch is contained"
  fi
else
  row 7 "branch dependency" "SKIP" "no git repository or fetch failed"
fi

# ---------------------------------------------------------------------------
echo
if [ -s "$sec" ]; then
  echo "secret scan hits:"
  sed 's/^/  /' "$sec" | cut -c1-160
  echo
fi
if [ -n "$SUSPECT" ]; then
  echo "suspect files by extension:"
  printf '%s\n' "$SUSPECT" | sed 's/^/  /'
  echo
fi
if [ -n "$BIG" ]; then
  echo "oversized additions:"
  printf '%s\n' "$BIG" | sed 's/^/  /'
  echo
fi

if [ "$fails" -gt 0 ]; then
  echo "TIER 1 FAILED: $fails check(s). Fix these before spending anything on tier 2 or later."
  exit 1
fi
echo "TIER 1 PASSED. Warnings above are triage material, not blockers."
exit 0
