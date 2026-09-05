#!/bin/sh
# PreToolUse advisory hook on Agent. Injects the routing checklist before every
# subagent call, even when the agent-spec skill was never invoked.
#
# WHY. A rule written in CLAUDE.md fades after ten or fifteen turns. The decision
# point it governs — which model, how many lenses, what the prompt must contain —
# arrives later, and by then the rule is not in the room. This hook puts it there.
#
# Non-blocking. Pairs with agent-prompt-block.sh, which hard-blocks the prompt
# anti-patterns after this classification has been made.

set -e

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Agent" ] || exit 0

st=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
case "$st" in
  Plan|Explore|statusline-setup|claude-code-guide) exit 0 ;;
esac

reminder='Pre-Agent checkpoint (agent-spec skill):

1. CLASSIFY by failure-recovery cost — what happens if the agent misses something,
   invents something, or is confidently wrong?

   IRRECOVERABLE (security, migration mechanics, an architectural decision, closing
   out a phase, a production incident) -> multi-lens: 3+ parallel top-model agents
   with DISJOINT lenses, or an existing skill (phase-reaudit, pre-merge-audit,
   security-review). A single mid-tier subagent is FORBIDDEN here: its false
   negative reads as "all clear" and closes the question.

   RECOVERABLE (lookup, implementation in a known area, non-production debugging,
   a refactor plan) -> route by type. Cheap model for lookup / transform /
   extraction, mid-tier for research / implementation / review, top-tier for
   decomposition and comparison. Start cheaper, escalate on acceptance-gate fail.

   BORDERLINE (a code review whose content touches migrations, auth, crypto,
   money) -> classify as irrecoverable.

2. NAME THE MODEL EXPLICITLY. An omitted model does not mean "cheap by default" —
   it inherits the session model, which is usually the most expensive one. Also:
   turn count beats per-token price. A cheap model on multi-step work takes two to
   three times the turns and ends up costing more. Floor: any reviewer, and any
   agent working from a description rather than from finished text, gets at least
   a mid-tier model.

3. PROMPT STRUCTURE — six blocks, or agent-prompt-block.sh rejects the call:
   context / one narrow disjoint scope / deliverable schema / out-of-scope /
   permission to say NOT_FOUND / file:line claims you verified yourself first.

4. ACCEPTANCE GATE after it returns: output much shorter than the scope, zero
   file:line citations, everything phrased as "consider" or "may need",
   NOT_FOUND where material obviously exists, self-contradiction. Two or more of
   those means the agent did not do the work. Recoverable -> one retry with an
   upgrade. Irrecoverable -> escalate, do not retry the same configuration.

Invoke the agent-spec skill for the full version.'

jq -n --arg ctx "$reminder" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx, permissionDecision: "allow"}}'
