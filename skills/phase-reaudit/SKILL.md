---
name: phase-reaudit
description: "Multi-lens parallel audit of a formally closed phase or any milestone document. Spawns four to five specialized agents in parallel (citation accuracy, plan coherence, fix architecture, severity and ripple). Use BEFORE merging a security or architectural milestone, or AFTER noticing the symptom that a formal definition of done was met while the system does not work. Catches roughly half of what self-review misses."
---

# Phase re-audit

Run this skill when:
- A security or architectural phase is formally closed and you suspect dirty corners.
- A new remediation or plan document needs verification before merge.
- The user asks whether you cut corners.

Do NOT use for:
- A single-file code review (read it and think).
- Trivial bug fixes.

## What it does

Spawns four parallel agents with DIFFERENT lenses. Each must back every finding
with a code citation, file, line, quote. No "probably" or "likely": verified or
omitted.

## How to invoke

Ask the user for:
1. **The target**: a phase identifier, a document path, or a scope ("everything from phase 1 to 10").
2. **Which code roots to scan** (default: the project root).

Then dispatch four agents in parallel, each with a distinct prompt. Every prompt
carries the six blocks required by `agent-spec`, the last three matter most here:
a hard output format, an explicit out-of-scope list naming the other three lenses,
and permission to write NOT_FOUND.

### Agent 1 — Citation accuracy
For every claim in the document that cites file and line, open the file and check
that the line says what is claimed. Verdicts: CONFIRMED / STALE_LINE /
HALLUCINATED. Output as a table.

### Agent 2 — Plan coherence
Check the document against everything around it: README, progress tracker,
decisions log, dependent phase documents. Find direct contradictions, duplicated
work, wrong sequencing claims, missing back-references, scope mismatches.

### Agent 3 — Fix architecture
For each proposed fix, judge: does it solve the problem, does it break something
else (read the related code, do not reason about it), is the migration path
workable, does it conflict with an existing constraint. Cherry-pick the ten to
twenty highest-impact items rather than covering everything shallowly.

### Agent 4 — Severity and ripple
Part one: re-evaluate the severity tags. Look for inflated criticals, and for
underrated continuous data leaks or silent corruption.
Part two: third-order ripple, for each critical, what does fixing it unblock or
break in other phases and services? Find ordering deadlocks.

## After the agents return

Consolidate into a single triaged list. Then update the target document with:
- severity corrections;
- rewritten dangerous fixes;
- architectural changes split out from bug fixes (these need entries in the decisions log);
- corrected migration mechanics (add-constraint-not-valid then validate, for populated tables);
- a corrected time estimate, typically two to three times the original guess.

Accept the verdicts selectively, by checking them. **An agent that removed a
problem from view is more dangerous than one that invented a problem.**

## Cost

Five to ten minutes, 50-100K tokens across the agents. Worth it for security and
architecture milestones; overkill for routine work.

## Origin

A five-agent re-audit of five phases found 34 verified bugs, nine of them
critical — AFTER every one of those phases had been formally closed. A follow-up
four-agent re-audit of the remediation document itself found around twenty more
issues, including fixes that would have broken production. Self-review had caught
roughly half.
