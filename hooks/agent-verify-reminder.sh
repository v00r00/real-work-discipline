#!/bin/sh
# PostToolUse hook on Agent. After a subagent returns, injects a checklist:
# did it answer the questions that were asked, or something adjacent?
#
# WHY. Drift is quiet. The agent reframes the question slightly, answers its own
# version, summarises where you asked for citations, and skips the numbered item
# it had no data for — without saying so. The answer looks complete, so it gets
# used. This is the same failure as trusting your own memory over the file, one
# level removed.
#
# Warns, never blocks.

set -e

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Agent" ] || exit 0

subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
description=$(printf '%s' "$input" | jq -r '.tool_input.description // empty')

ctx=$(cat <<EOF
[Subagent verify checklist]

Returned: subagent_type=${subagent_type}, description="${description}".

BEFORE using this answer for an edit, a decision, or another delegation:

1. RE-READ YOUR OWN PROMPT. Which enumerated items did you ask for? Which exact
   file:line did you ask to be confirmed? Which questions did you number?

2. WALK THE ANSWER against that list. Was each item answered specifically — or
   did you get a general summary, a different framing, or "roughly X" where you
   asked for an exact citation?

3. DRIFT SIGNALS, each one needs a follow-up:
   - "typically", "usually", "should be" instead of a verified file:line.
   - A prose summary where you asked for a structured shape.
   - The agent reformulated the question and answered its own version.
   - An enumerated item missing, with no explicit "not found" / "not applicable".

4. FOR ANY MISSING OR OFF-TOPIC ITEM — do not start implementing. Either send a
   follow-up message to the same agent naming the missed question, or open the
   file and check it yourself (faster for a single citation), or reconsider the
   scope if the answer shows the task meant something else.

5. An unverified subagent claim has the same standing as your own memory: none.
   Do not write code on top of one.

If you have already walked the list and every item is covered, ignore this. The
target is the case where the agent gave 90% of an answer and the missing 10% is
where the work actually was.
EOF
)

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
