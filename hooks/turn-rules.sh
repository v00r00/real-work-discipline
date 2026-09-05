#!/bin/sh
# UserPromptSubmit hook. Prints the four release blockers before every turn.
#
# Every prompt pays for this text, so keep it short and keep it about the four
# blockers. Project-specific policy belongs in the project's CLAUDE.md.

cat <<'RULES'
Rules for this turn:

1. SHIP IT. Work ends, it does not improve. Exactly four kinds of finding stop a
   release: a regression (something that worked is now broken) · a false claim in
   code or a document · irreversible harm to a person or their data · breaking the
   law. EVERYTHING else is a tracker entry and the work continues. "The check
   doesn't catch everything", "coverage is partial", "this could be stricter",
   "found it outside my area", "the gap predates this change" — entries, not stops.

2. "DONE" IS WRITTEN BEFORE THE WORK STARTS AND DOES NOT CHANGE. Anything found
   along the way — your own ideas, review findings, subagent remarks — goes to the
   tracker and does NOT extend the current work. Ever. Sign of violation: the work
   is on its second day and is larger than when it started. Second sign: the report
   of findings is longer than the description of what was done.

3. YOU DO THE TRIAGE AND YOU OWN IT. Exactly four kinds of question go to the
   user: product policy · an irreversible action · a permission only they can
   grant · a dispute over severity where the cost of being wrong is asymmetric.
   Relaying findings to the user is NOT a decision.
RULES
