---
name: agent-spec
description: "MUST be invoked BEFORE any Agent tool call. Classifies the task by failure-recovery cost (irrecoverable vs recoverable), picks the model and effort, and dictates a prompt structure that matches the agent-prompt-block hook. For security, architecture and migration work the bias is to the top model plus multiple disjoint lenses; a single mid-tier subagent is forbidden there."
metadata:
  type: workflow
---

# agent-spec — pre-flight for the Agent tool

## Step 0. Is a subagent needed at all

A subagent is justified if **at least one** holds:
- the task takes more than three tool calls and would flood the main context;
- there are N independent tasks that can run in parallel;
- it is read-only research whose output should not steer the main reasoning;
- it is a multi-lens audit (step 2.A).

A subagent is NOT needed if:
- it is one or two greps, do it yourself;
- it needs a dialogue with the user (an agent cannot ask);
- the task is irrecoverable AND small enough to do yourself -> **default to doing it yourself**.

## Step 1. The primary axis — recovery cost of the agent being wrong

Ask: **"what happens if the agent missed X, invented Y, or was confidently wrong?"**

### Irrecoverable (high stakes)
Failure produces an outcome you **cannot undo within an hour**:
- a security breach, leaked personal data, exposed credentials;
- data loss or silent data corruption;
- a production outage;
- migration mechanics against a populated table;
- an architectural contract change a downstream consumer already depends on;
- a decision that blocks a week or more of someone's work;
- a legal or compliance violation;
- closing a phase on a false "all green", which then drifts through the next phase.

**The tell:** the agent's false negative **does not show up in the diff** and will
slide past review.

### Recoverable (low stakes)
Failure is visible immediately or caught by a cheap retry:
- the lookup found the wrong file (obvious at once);
- the refactor plan is bad (revised before any commit);
- a typo or boilerplate mistake (tests or the diff catch it);
- a bug in a known area (tests catch it).

**The tell:** the error is either visible in the output or caught by automated
tests and a diff scan.

### Borderline
A code review of an ordinary pull request, it depends on the content:
- migrations, auth, crypto, money -> **irrecoverable**;
- docs, UI copy, a log line -> **recoverable**.

When in doubt, classify as **irrecoverable**: the cost of being wrong is asymmetric.

## Step 2. Routing

### 2.A — Irrecoverable

**Rule: a single subagent is forbidden.** The options are:

1. **Multi-lens fan-out**: three or more parallel top-model agents with
   **disjoint lenses**:
   - citation accuracy / facts
   - plan coherence / internal logic
   - severity and ripple / downstream impact
   - optionally: fix architecture / contract design
   - high effort for each
   - **you** do the synthesis, not another agent.
2. **The no-agent path**: if the scope is small enough to read yourself: open the
   files, grep, think it through in the main session with the user in the loop.
   Delegating irrecoverable work to a cheap model is the anti-pattern this whole
   skill exists to prevent.
3. **An existing skill**: `phase-reaudit` for closing a phase, `pre-merge-audit`
   for a pull request with security or migration content, `security-review` for a
   standalone pass. **These are already multi-lens. Use them instead of an ad-hoc
   agent.**

**Downgrading to a cheaper model is forbidden even "just for a quick check".** A
false negative on security reads as "all clear" and closes the question. The cost
of being wrong dwarfs the cost of the upgrade.

### 2.B — Recoverable

| category | model tier | effort |
|---|---|---|
| Lookup / grep / file listing | cheap | — |
| Mechanical transform, boilerplate | cheap | — |
| Structured extraction against a schema | cheap | — |
| Multi-step research across files | mid | — |
| Implementation in a known area | mid | — |
| Code review (non-security) | mid | — |
| Refactor plan (internal, reversible) | mid | — |
| Root-cause on a non-production bug | mid -> top on acceptance-gate fail | standard |
| Decomposing an ordinary feature | mid -> top on acceptance-gate fail | standard |

**Bias to the cheap model only in this branch.** An acceptance-gate failure
(step 4) means retry with an upgrade.

### 2.C — Name the model EXPLICITLY on every call

**An omitted model does not mean "cheap by default", it inherits the session
model.** Check which one that is: `grep '"model"' ~/.claude/settings.json`. If the
session runs the top tier, then every agent without an explicit model runs there
too, and the whole of table 2.B silently evaporates. Fill in the `model` parameter
**always**, even when the answer is "same as the session".

**Turn count beats price per token.** Spend is driven by how many turns the
agent took, not by the model's rate. A cheap model on multi-step work takes two to
three times the turns and ends up more expensive than a mid-tier model that did it
in one pass. Hence the floors:

| work | model |
|---|---|
| the finished text or code is in the prompt; the agent transfers and checks it | cheap |
| a single mechanical edit in one file | cheap |
| **any reviewer** | mid-tier — this is a floor, do not go below it |
| **any implementer working from a description in words rather than from finished code** | mid-tier — floor |
| irrecoverable (step 2.A) | top tier, not negotiable |

**Effort is a second setting, and the `Agent` tool cannot set it**: it is
inherited from the session. If you need a guaranteed high effort level, run
through `Workflow`, which has its own parameter for it. If your lenses ran through
`Agent`, say so honestly in the report: "effort inherited from the session, not set".

## Step 3. Prompt structure (matches the agent-prompt-block hook)

Any prompt longer than 500 characters must carry six blocks. Without them the
hook rejects the call.

1. **Context**: what you already know, what you ruled out, why you need this.
   Not "find X" but "I am testing the hypothesis that Y".
2. **One narrow scope**: one agent, one disjoint area. Otherwise split.
3. **Deliverable schema**: "a table of N columns", "a list of at most 8", "JSON
   with these fields". Without a schema you get generic prose.
4. **Out of scope**: "do not touch Y / no web search / do not propose fixes".
5. **Permission to not know**: "if you cannot find it, write NOT_FOUND and where
   you searched, do not guess".
6. **Verify before citing**: any `file:line` claim in the prompt is one you
   **opened yourself before spawning**. Do not ask an agent to verify your claim;
   it will agree with you.

**The hook matches literal words, not meaning.** Wording that is correct in
spirit still gets the call rejected. Use these literally:

| block | a word that must appear |
|---|---|
| deliverable schema | `final:`, `output format`, `summary in N lines` |
| out of scope | `do not`, `out of scope`, `avoid` |
| permission to not know | `NOT_FOUND`, `do not guess` |

## Step 4. Acceptance gate (after it returns, before you use the result)

| signal | what it means |
|---|---|
| output is ~30% shorter than the scope | items were skipped |
| zero `file:line` citations in a research result | it never opened the files |
| every finding phrased as "consider" / "may need" | no ground truth |
| NOT_FOUND everywhere the context says material exists | early give-up |
| self-contradiction (A and B both asserted where A excludes B) | no coherence |
| no counter-examples from your own context | negative cases were not checked |

**If two or more signals fire:**

- **Recoverable** -> retry with an upgrade (better model, or higher effort). One
  retry maximum. A second failure means the no-agent path.
- **Irrecoverable** -> **escalate, do not retry**: add more lenses, ask a human, or
  work it through yourself. Retrying the same configuration is pointless, the
  model was already top tier, and one more roll will not produce what was not there.

## Step 5. Parallelism

More than one independent task means **one message with N Agent calls**, not a
sequence.

Independence test: the output of A is not an input to B.

Limits:
- recoverable: 4 parallel at most;
- irrecoverable multi-lens: 3 to 5 lenses (fewer than 3 is not multi-lens; more
  than 5 costs more in context and synthesis than it returns).

## Step 6. When to skip this skill

- The built-in `Plan` / `Explore` / `statusline-setup` / `claude-code-guide` agents
 , exempt in the hook, and the full skill would be overkill.
- A recoverable lookup under 500 characters on a cheap model, step 0 plus basic
  routing is enough.
- **Do not skip** if any irrecoverable signal is present, however small the prompt.
  A small security review is still a security review.
