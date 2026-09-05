#!/bin/sh
# PreToolUse hook on Bash, matching `gh pr merge`. Prints four questions before a
# merge and ALWAYS lets it through.
#
# INVARIANT: there is no exit 2 in this file, and adding one is a regression.
# It does not call the network either, for the same reason. Why, at length: the
# repository README. In short, both were tried and both blocked merges hardest
# at the moments they knew least.

set -e

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Bash" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

echo "$cmd" | grep -qE '(^|[&;|][[:space:]]*)gh[[:space:]]+pr[[:space:]]+merge\b' || exit 0

RELEASE=""
if echo "$cmd" | grep -qE '(--base|-B)[[:space:]]+(main|master)([[:space:]]|$)'; then
  RELEASE=1
fi

cat >&2 <<'EOF'
BEFORE MERGING — four questions. "No" to all four means merge.

  1. REGRESSION — is something that worked now broken?
  2. FALSE CLAIM — does the code or a document say something untrue about itself?
  3. IRREVERSIBLE HARM to a person or their data?
  4. BREAKING THE LAW?

Everything else — "the check doesn't catch everything", "coverage is partial",
"this could be stricter", "the gap predates this change", "the defect is in
someone else's area" — IS A TRACKER ENTRY, AND THE MERGE PROCEEDS.

You do the triage and you own it. Exactly four kinds of question go to the user:
product policy · an irreversible action · a permission only they can grant · a
dispute over severity with an asymmetric cost of being wrong. Relaying findings
is not a decision.

The audit skill is called BY RISK AREA, not for every pull request: migrations ·
authentication and authorization · crypto and secrets · infrastructure and
deployment · paths that carry personal data · a contract between services.

Sign the rule is being broken: a third round of checking on one piece of work
while the production behaviour did not change between rounds. That means there
is no triage — not that the work is bad.
EOF

if [ -n "$RELEASE" ]; then
  cat >&2 <<'EOF'

This merge targets main — it is a release. Not blocked, just named. If your
post-merge automation runs from the target branch, it will run the version that
lives there, which may be older than what you just tested. Worth one look before
you call it shipped.
EOF
fi

exit 0
