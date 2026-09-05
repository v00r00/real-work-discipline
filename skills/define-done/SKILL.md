---
name: define-done
description: "Invoke at the very start of work that will not close in one pass: a new capability, a rebuild, a task with several steps, anything where done is not obvious and you will have to come back to it. Invoke mid-work too if the work is on its second day and larger than when it started, or if after a context compaction it is unclear what is already finished - both mean done was never written down or has quietly moved. Do not invoke for a one-line fix, a single question, or exploration whose output is an answer rather than code."
---

# define-done — "done" is written before the work starts

## Why this skill exists

Nothing ever shipped, and it was never for want of a server. Work did not finish
because "done" meant "no findings left", and findings do not run out: every
instrument can be sharpened, every guard has a mutation it misses.

The skill does exactly three things, all three against the same disease:

1. **writes "done" to a file before the first edit**: so it cannot be moved quietly;
2. **cuts the work into steps of two to five minutes**: so "finished" is visible rather than remembered;
3. **keeps an execution log on disk**: so a context compaction does not erase what was done.

## Step 0. Name the size out loud

Before asking anything else, say which kind of work this is. The user will
correct you if they disagree. Do not guess silently.

| kind | what it is | how it ends |
|---|---|---|
| **probe** | "is this even possible", "will it hold", "does such a thing exist" | an answer and a recommendation. Everything written is marked disposable |
| **bounded** | a change to something that already exists and can be opened and read | a short description of the intent in chat, agreement, then work. No plan file |
| **large** | new behaviour, a new subsystem, a change to a contract between services, a migration | a plan file and a log file |

**The ratchet turns one way.** Complexity that surfaces mid-work **raises** the
kind: stop, say so out loud, rewrite "done". Lowering the kind mid-work is not
allowed, that is exactly how a "bounded" change becomes a three-day one with
nothing written down.

**"Bounded" is measured by the repository, not by your confidence.** If the
code path being changed cannot be opened and read, the work is not bounded, even
if you know exactly how to do it.

## Step 1. One sentence: "done"

Written **before** the first edit. One sentence. Checkable by eye or by a command.

| works | does not work |
|---|---|
| "the shopping list multiplies quantities by household size, verified live for a household of three" | "the shopping list works correctly" |
| "the ingredient table has 1609 rows and a menu builds with non-empty variety" | "fix the ingredient table" |
| "five skills edited, every description under the limit, all committed" | "tidy up the skills" |

**Sign of a bad sentence:** you cannot name the command or the screen that would
show it is satisfied. "No findings left" is always a bad sentence, findings do
not run out.

**If the sentence will not write, the task is not understood yet, and that is
not a reason to write it approximately.** Invoke `grill-me`: it interrogates in
rounds down the decision tree and produces exactly this sentence, confirmed by
the user. An approximate "done" drifts just as quietly as an unwritten one.

For large work, "done" is the first line of the plan file. For bounded work, it
is a sentence in chat before you start. After that it **does not change**. The
only thing entitled to rewrite it is a raise of the kind on the ratchet, and that
is done out loud.

## Step 2. The plan (large work only)

File: `<TOPIC>-PLAN.md` in the root of the working directory.

Header:

```markdown
# <Topic>

**Done:** <the one sentence from step 1>
**Kind:** large
**Verified by:** <a command or a screen>

## Constraints common to every task
<exact values from the project's decisions: versions, thresholds, names. One line each>
```

Then the tasks. **Each step is one action, two to five minutes:**

```markdown
### Task N. <name>

**Files:** create `exact/path.rs`, edit `exact/path.rs:120-140`, test `tests/path.rs`
**Takes from earlier tasks:** <exact names and types>
**Hands to later tasks:** <exact names and types>

- [ ] Step 1. Write the failing test — <the actual test code>
- [ ] Step 2. Run it, confirm it fails, `<command>`, expect `<failure text>`
- [ ] Step 3. Minimal implementation — <the actual code>
- [ ] Step 4. Run it, confirm it passes, `<command>`
- [ ] Step 5. Commit
```

**Placeholders are plan defects, not shorthand:**
"TBD", "finish later", "add error handling", "cover the edge cases", "same as task N" (repeat the code: tasks get read out of order), a step with no
verification command, a reference to a function no task creates.

**Review your own plan once, by eye, without agents:** walk the "done" sentence
clause by clause and point at the task that closes each one, look for the
placeholders listed above, check names and types line up between tasks
(`clearLayers` in task 3 and `clearFullLayers` in task 7 is a defect). Fix what
you find on the spot and move on. There is no second review.

## Step 3. The execution log

File: `<TOPIC>-PROGRESS.md` next to the plan. **Kept whenever there is a plan.**

**The conversation does not survive compaction; a file does.** Without the log,
after a compaction you cannot tell finished from unfinished, and the work gets
redone from scratch, the most expensive failure observed. Commits named in the
log are in git even when the context no longer remembers making them. **After a
compaction, trust the log and `git log`, not yourself.**

Format, one line per event, appended, never rewritten:

```
# Log — plan: <path to the plan file>
Done: <the sentence from step 1>

Task 1: closed, commit a1b2c3d, tests 34/34
Task 2: fix round 1, review found <what>
Task 2: closed, commit e4f5g6h, tests 35/35
Decision: <what was decided> — <why> — <what it costs if wrong>
Entry: <a finding that is not going into this work> — <where it was filed>
Task 3: minor thing deferred — <one line>
```

The line `Task N: closed` is the only proof a task is finished. No line, no task,
however much it feels otherwise.

## Step 4. What makes work longer, and what does not

**Exactly four kinds of finding extend the work.** Everything else is an `Entry:`
line in the log and the work continues:

| finding | what happens |
|---|---|
| regression: something that worked is broken | **fix now** |
| a false claim in code or a document | **fix now** |
| irreversible harm to a person or their data | **fix now** |
| breaking the law | **fix now** |
| "the check doesn't catch everything", "could be stricter" | entry, carry on |
| a gap that predates this change | entry, carry on |
| a defect in someone else's area, found in passing | entry, carry on |
| your own idea, "while we're here" | entry, carry on |

**Decisions get made, not deferred.** A contradiction in the plan, an ambiguity, a
defect in the plan itself, decide, write a `Decision:` line with the cost of
being wrong, and move on. Work that stops to wait for an answer costs the user a
whole day and buys nothing; a wrong decision costs a rework you can see and undo.

**Stop and ask the user for exactly four reasons:** product policy, an
irreversible action, a permission only they can grant, a dispute over severity
where the cost of being wrong is asymmetric. **Relaying findings to the user is
not a decision.**

## Step 5. Closing

1. Open the plan file and READ the recorded "done" sentence, do not recall it.
2. Run the command or open the screen named in "Verified by". Put the output in your answer.
3. Walk the log: does every task have a `closed` line?
4. Collect every `Entry:` line into one list and file them where the project's
   findings live. **A log nobody transferred is findings quietly thrown away.**
5. Say what was done, and **separately** what stayed as entries and why.

**The report of findings must not be longer than the description of what was
done.** If it is, the work has been replaced by collecting findings.

## Excuses

| the thought | what is actually true |
|---|---|
| "too simple to bother writing done" | simple things finish fast — the sentence costs ten seconds and stops it growing |
| "done is obvious here" | an obvious "done" cannot be moved quietly. An unwritten one can, and that is what happened every time |
| "the log is bookkeeping, I remember" | context compacts without warning. After that, "I remember" is a guess |
| "while we're here, I'll just fix this too" | that is new work. `Entry:` line, carry on |
| "the review found more, I should check" | not one of the four kinds — entry. One of the four — fix. There is no third option |
| "the scope grew because the task turned out harder" | then raise the kind out loud and rewrite "done". Growing silently is not allowed |
| "almost finished, too late to re-scope" | hidden complexity raises the kind at any moment. "Almost" lasts longest |

## Related skills

- Before step 1, when the "done" sentence will not write, `grill-me` (rounds of questions; its output is that sentence).
- Before any subagent call, `agent-spec` (kind of work, model, acceptance of the answer).
- Before merging a pull request in a risk area, `pre-merge-audit`; the round counter lives there too.
- To check `file:line` citations in the plan you just wrote, `verify-claims`.
- The whole path from uncommitted to merged, `full-github-pipeline`.
