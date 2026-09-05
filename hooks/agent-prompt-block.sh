#!/bin/sh
# PreToolUse hook on Agent. HARD-BLOCKS a subagent call whose prompt steps on one
# of seven anti-patterns, before the subagent is spawned rather than after.
#
# exit 2 -> the harness rejects the Agent call and shows stderr to the model,
# which rewrites the prompt and retries.
#
# INVARIANT: no bypass switch. This fires exactly when nobody feels like being
# careful. Too noisy for your work? Remove it from settings.json; do not add an
# escape hatch to it.
#
# Exempt agents: the built-ins whose prompts are short or schema-less by nature.
#
# KEEP IN SYNC with the agent-spec skill: rules 4, 5 and 6 match on literal
# wording, so the skill tells you which words to use. Change one, change both.

set -e

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
[ "$tool" = "Agent" ] || exit 0

st=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // "general-purpose"')
case "$st" in
  Plan|Explore|statusline-setup|claude-code-guide) exit 0 ;;
esac

prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // empty')
[ -z "$prompt" ] && exit 0

warnings=""

# Short lookup-style calls skip the soft rules (4, 5, 6): three mandatory blocks
# of boilerplate on a three-line prompt is friction for nothing. Rules 1, 2, 3
# and 7 are always on.
prompt_len=$(printf '%s' "$prompt" | wc -c)
[ "$prompt_len" -lt 500 ] && short_prompt=1 || short_prompt=0

# 1. Fat prompt — the indirect signal for "use more agents".
if [ "$prompt_len" -gt 4000 ]; then
  warnings="${warnings}#1 FAT PROMPT (${prompt_len} chars). Split into 2-4 parallel narrow agents with disjoint scope. One fat agent silently ranks your low-priority questions last and drops them. Rule of thumb: 1 agent = 1 narrow area, <= 8 enumerated questions.
"
fi

# 2. Information overload — count enumerated items.
items=$(printf '%s' "$prompt" | grep -cE '^[[:space:]]*([0-9]+\.|-|\*\*[A-Z][0-9]*\.|[A-Z][0-9]+\.)' || true)
if [ "$items" -gt 18 ]; then
  warnings="${warnings}#2 OVERLOAD: ${items} enumerated items. The agent will start degrading around item N+5. Split into narrow agents.
"
fi

# 3. Mixed research + fix framing. Strip negated forms ("do not propose") before
# counting the proposal keywords, or the negation itself trips the rule.
prompt_for_prop=$(printf '%s' "$prompt" | sed 's/do not propose[^.]*//gi; s/don.t propose[^.]*//gi; s/do not suggest[^.]*//gi')
desc=$(printf '%s' "$prompt" | grep -ciE 'describe|verify|read.only|inventory|do not propose' || true)
prop=$(printf '%s' "$prompt_for_prop" | grep -ciwE 'propose|fix|refactor|implement|design|plan' || true)
if [ "$desc" -ge 1 ] && [ "$prop" -ge 1 ]; then
  warnings="${warnings}#3 MIXED FRAMING: the prompt asks to describe the current state AND to propose fixes. The agent will slide into planning and under-describe the state. Split: one read-only research call, then a planning call.
"
fi

# 4. No explicit deliverable schema.
deliv=$(printf '%s' "$prompt" | grep -ciE 'final:|deliverable|output format|response format|report format|return.*(as|in) (a )?(table|list|json)|table of|summary in [0-9]|at most [0-9]+ (lines|items|rows)' || true)
if [ "$short_prompt" = 0 ] && [ "$deliv" -eq 0 ]; then
  warnings="${warnings}#4 NO DELIVERABLE SCHEMA: end the prompt with an explicit shape - 'final: 1) a table of N columns 2) summary in <= 5 lines 3) flag WRONG if ...'. Without a schema you get generic prose.
"
fi

# 5. No "what NOT to do" / no scope bound.
neg=$(printf '%s' "$prompt" | grep -ciE "do not|don'?t|avoid|out of scope|out-of-scope|stay out of|skip the|no web search" || true)
if [ "$short_prompt" = 0 ] && [ "$neg" -eq 0 ]; then
  warnings="${warnings}#5 NO 'DO NOT': the scope is unbounded and the agent will wander. Add 'do not touch Y / no web search / do not propose fixes / out of scope: Z'.
"
fi

# 6. No permission to not know.
unknown=$(printf '%s' "$prompt" | grep -ciE 'NOT_FOUND|not found|do not guess|don.t guess|mark as unknown|say so explicitly|if it is missing|if absent' || true)
if [ "$short_prompt" = 0 ] && [ "$unknown" -eq 0 ]; then
  warnings="${warnings}#6 NO 'ADMIT IGNORANCE': without it the agent quietly guesses instead of reporting a gap. Add: 'if you cannot find it, write NOT_FOUND and where you searched - do not guess'.
"
fi

# 7. file:line claims inside the prompt.
fline=$(printf '%s' "$prompt" | grep -oE '[a-zA-Z_/.]+\.(rs|java|py|ts|js|kt|go|rb|sql|yml):[0-9]+' | head -3 || true)
if [ -n "$fline" ]; then
  fline_csv=$(printf '%s' "$fline" | tr '\n' ' ')
  warnings="${warnings}#7 WRONG-CLAIM RISK: the prompt cites file:line (${fline_csv}). Open those lines YOURSELF before delegating - an agent will rubber-stamp a false claim you sound confident about.
"
fi

[ -z "$warnings" ] && exit 0

printf 'AGENT PROMPT BLOCKED — anti-patterns detected:\n\n' >&2
printf '%s' "$warnings" >&2
printf '\nFix the prompt and retry. Common rewrites:\n' >&2
printf '  #1 fat        -> split into N parallel narrow agents with disjoint scope\n' >&2
printf '  #2 overload   -> <= 8 questions per agent\n' >&2
printf '  #3 mixed      -> first call: read-only research; second call: planning\n' >&2
printf '  #4 no shape   -> "final: 1) table of N columns 2) summary in <= 5 lines 3) flag WRONG if ..."\n' >&2
printf '  #5 no DO-NOT  -> "do not touch Y / no web search / do not propose fixes / out of scope: Z"\n' >&2
printf '  #6 no gap     -> "if you cannot find it, write NOT_FOUND and where you searched"\n' >&2
printf '  #7 file:line  -> read the lines yourself first, put the real numbers in the prompt\n' >&2
exit 2
