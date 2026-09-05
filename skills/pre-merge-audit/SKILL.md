---
name: pre-merge-audit
description: "Invoke when a pull request is ready to merge and the change touches a risk area: migrations, authentication and authorization, crypto and secrets, infrastructure and deployment, paths carrying personal data, a contract between services. Invoke also when the pull request has no approving review and correctness rests on self-check. Not for every pull request, and not by diff size - by risk area. THE GOAL IS TO LET GOOD WORK THROUGH, not to find bad work: exactly four kinds of finding block a merge (a regression, a false claim, irreversible harm to a person or their data, breaking the law) and everything else becomes a tracker entry."
---

# Pre-merge audit

## THE GOAL IS TO LET GOOD WORK THROUGH, NOT TO FIND BAD WORK

**Read this first.** The point of the work is to ship. The audit exists to **keep
harm out**, not to accumulate findings: findings will always exist, and any
instrument can be sharpened forever.

**The audit is over when every finding has a decision, not when there are no
findings left.**

| finding | verdict |
|---|---|
| regression: something that worked is broken | **FAIL** |
| a false claim in code or a document | **FAIL** |
| irreversible harm to a person or their data | **FAIL** |
| a coverage gap that existed BEFORE this change | **PASS + tracker entry** |
| "the check doesn't catch everything", "could be stricter" | **PASS + tracker entry** |
| a defect in someone else's area, found in passing | **PASS + tracker entry** |

**The key distinction.** "The check does not catch mutation X" is not a defect
of this change if before the change it caught nothing at all. The state improved.
Demanding completeness of a first step is the same as forbidding first steps.

**The assistant does the triage and owns it.** Exactly four kinds of question
go to the user: product policy, an irreversible action, a permission only they
can grant, a dispute over severity with an asymmetric cost. **Relaying the
lenses' findings to the user is not a decision.**

**Sign of violation:** a third audit round on one piece of work while the
production behaviour did not change between rounds. That means there is no triage
— not that the work is bad. Precedent: two full rounds of lenses on one pull
request, zero merges, and not a byte of production code touched.

---

**Called by the risk of the change, not for every pull request.** Mandatory when
the change touches: migrations, authentication and authorization, crypto and
secrets, infrastructure and deployment, paths carrying personal data, a
contract between services.

Everything else is the assistant's judgement. The older rule, "even a one-line
change needs an audit", was cancelled: its cost was not thoroughness, it was
fourteen checks standing in front of a documentation edit while nothing shipped.

The argument that rule was written for remains true: an auto-formatter can
silently rewrite two hundred files, and an IDE refactor can drop an "unused"
import that was load-bearing. That is why the list above names an **area**, not a
size, and why the cheap machine tier below runs always. It catches exactly that
class in a fraction of a second without a full audit.

## What it does

Ten independent checks against the pull request head versus its base, in four groups:

**A. State checks (fail fast, cheap)**: if the request is in a bad git state, the rest is pointless.
**B. Content checks**: what is in the diff.
**C. Architecture checks**: how the change affects the repository, other requests, production.
**D. Correctness review**: reading the changed code. Mandatory when there is no approving review: checks 1-9 measure hygiene and will happily return nine passes on incorrect but tidy code.

Any FAIL blocks the merge until cleanup. A completed triage writes a marker file
for downstream hooks.

## How to invoke

Ask the user for the **pull request identifier** (`owner/repo#123`, or `#123` if
the working directory is the repository).

---

## TIERS AND STOPS — read before anything else

**The audit runs in tiers of increasing cost. Between tiers there is a STOP: fail
a tier and the next one does not run.** Inside a tier, run everything and print
every failure at once, so one repair cycle closes them all.

| tier | what | how | cost |
|---|---|---|---|
| **1** | text, git, files | `~/.claude/tools/audit-tier1.sh <PR>` | under a second |
| **2** | is the running stack built from this commit | `~/.claude/tools/audit-tier2.sh <head-sha>` | seconds |
| **3** | test runs: unit, integration, CI on the head | your build | minutes |
| **4** | judgement: lenses, refuters, end-to-end with seeded data | sections D and E below | tens of minutes, hundreds of thousands of tokens |

Tier 1 needs nothing configured. Tier 2 reads
`~/.claude/discipline/audit-tier2.conf`, and without it says SKIP rather than
PASS: nothing was checked, and that is not the same as nothing being wrong.

Both scripts fail on an empty diff or an unreadable artifact instead of
reporting a clean run. Tier 1 opens by matching its own scanners against a
planted secret, because a scanner that cannot fire in this environment reports
"no matches" and reads exactly like good news.

**Why in that order.** One pull request went through FIVE rounds. The blocking
finding in FOUR of the five would have been caught by a one-second command, but
it was checked last, after a full multi-lens run:

| round | the blocking finding | what would have caught it |
|---|---|---|
| 1 | the built image came from the first of three commits | `grep` inside the artifact |
| 2 | the tracker described a method that had been deleted | `grep` for the method name |
| 3 | the end-to-end run was done on the previous commit | comparing two SHAs |
| 5 | the evidence file cited a stale head; two counters disagreed; nine entries were outside the plan | the whole of tier 1, in 0.4 seconds |

Tier 1 against the state of round 5 goes red **in a fraction of a second** and
stops the audit before a single token is spent on lenses.

### Rules common to EVERY tier

**R1. A zero without a positive control is not a result.** Any check reporting "no
matches" must, in the same run, show a non-zero result for something that must be
there. In one session, three separate tool failures looked like clean results: a
restore tool of the wrong version against a newer dump, a missing archive tool
inside a runtime image, a missing `strings` in the same image. Each printed "0
matches", and each was read as "the old code is gone".

**R2. Exit codes are not read through a pipe.** `cmd | tail` gives you the status
of `tail`. A script that returned 1 was reported as returning 0 on exactly this —
a failure read as a success.

**R3. Inspect artifacts on the host.** A runtime image deliberately has no tools
in it. Pull the file out (`docker cp`) and read it with something you have.

**R4. The reference point comes FROM THE FILE, not from memory.** Before writing
"verified on head X", grep the head out of the evidence file and diff from that.
Round 5 above survived precisely because the comparison was made against the head
that was remembered, not the head that was recorded.

**R5. THE RATCHET.** A round found a defect that a cheap check would catch -> **that
check is added to tier 1 or 2 in the same cycle**, not "sometime". Without this
the lower tiers freeze and everything leaks into the expensive ones. Every one of
those five rounds found a check that did not exist yet.

**R6. ESCALATION.** The same **class** of error surfaces a third time -> the audit
**stops** and goes to the user. Not another round. On that pull request the class
"the document describes code that is not there" surfaced four times in a row.
After the third, the right move was not a fourth round but saying out loud: this
approach is not working, we need a mechanism. Instead it cost two more days.

**R7. THE BREAKER: five rounds per pull request is the ceiling.** A round is one
repair pass plus one re-check of what was repaired. Number them out loud and put
them in the report: "round 3 of 5".

| round | what to do |
|---|---|
| 1-3 | repair and re-check normally |
| 4-5 | before repairing, say out loud why the previous rounds did not work; if there is no answer, that is R6 |
| **5 done, findings remain** | **there is no round six** — the breaker fires |

**What the breaker does.** Not "one more round", and not "hand everything to the
user". For **each** remaining finding, decide here and now:

- it falls in the four blocking classes (regression, false claim, irreversible
  harm, breaking the law) -> fix it. That is the only thing entitled to extend the
  work;
- it does not -> **tracker entry, the merge proceeds.** The entry must name what
  specifically was left unfixed; closing a finding silently is forbidden;
- the decision genuinely needs the user (product policy, an irreversible action, a permission, a severity dispute with asymmetric cost) -> escalate **that
  finding**, not the whole list.

**The counter exists because without it there is nothing to stop on.** R6 catches
a repeated class, but rounds can run without repeating, each with its own fresh
finding, each looking justified. Five rounds on one request, two rounds on
another with untouched production code: R6 would not have stopped either, because
the classes were all different.

**Rounds count from the first audit of this pull request, not from the last
repair.** Resetting the counter because "we're fixing something different now" is
exactly the move that makes rounds infinite.

---

## A. State checks (fail fast)

### 1. Conflicts (mergeable status)

```bash
gh pr view <N> --json mergeable,mergeStateStatus
```

- `mergeable: "CONFLICTING"` -> **FAIL**, needs a rebase.
- `mergeable: "UNKNOWN"` -> **WARN**, GitHub has not computed it yet; wait and repeat.
- `mergeStateStatus: "BEHIND"` -> **WARN**, head is behind base.
- `mergeStateStatus: "BLOCKED"` -> **FAIL**, branch protection is refusing (usually missing reviews, see check 3).
- `MERGEABLE` with `CLEAN` / `HAS_HOOKS` / `UNSTABLE` -> **PASS**.

### 2. Force-push since the last review

```bash
gh pr view <N> --json reviews,commits --jq '
  {
    last_review_at: (.reviews | map(.submittedAt) | max // null),
    last_commit_at: (.commits | map(.commit.committedDate) | max),
    last_commit_sha: (.commits | last | .oid)
  }'
```

If a review exists AND `last_commit_at > last_review_at` -> **WARN**. The reviewer
approved an older version and the current code is unreviewed. Either re-request
the review, or, if the changes since are cosmetic, acknowledge and proceed. If
they are substantive, stop and wait for a new review.

If there are no reviews at all, this check is **PASS** (their absence is check 3).

### 3. Review decision

```bash
gh pr view <N> --json reviewDecision,reviewRequests
```

- `APPROVED` -> **PASS**.
- `CHANGES_REQUESTED` -> **FAIL**, requested changes are unresolved.
- `REVIEW_REQUIRED` -> **FAIL** if branch protection requires reviews; **WARN** on a solo project.
- `null` -> **PASS**, but say so in the output table. This is the trigger for section D.

---

## B. Content checks

### 4. Description versus reality

```bash
gh pr view <N> --json additions,deletions,files --jq '"+\(.additions)/-\(.deletions), \(.files | length) files"'
gh pr view <N> --json files --jq '.files[] | "  \(.additions)+/\(.deletions)- \(.path)"'
gh pr view <N> --json title,body
```

Categorize the files. If the body says "X only" but the files include things
outside X -> **FAIL**, the body must be rewritten. This is not pedantry: a
description that does not match its contents is a false claim in a document, one
of the four blocking classes.

Bonus: the body should carry a `## Test plan` with real checked items. A body
that is a heading plus bullet points with no checked boxes -> **WARN**.

### 5. Extended secret scan

```bash
# Suspicious file types — any hit gets a manual look
gh pr view <N> --json files --jq '.files[].path' | grep -iE "\.(key|pem|crt|p12|pfx|env|envrc)$|(^|/)\.env(\.|$)"

# Private keys
gh pr diff <N> | grep -iE "BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY"

# Generic credential assignments, with a placeholder whitelist
gh pr diff <N> | grep -iE "^\+.*(api[_-]?key|secret|token|password|passwd|credential)[\"']?[ ]*[:=][ ]*[\"'][a-zA-Z0-9_/+=-]{20,}" \
  | grep -vE "CHANGE_ME|XXXX|<.+>|\\\$\{|\\\$[A-Z_]+|placeholder|example|REPLACE"

# JWTs — three base64url segments
gh pr diff <N> | grep -E "^\+.*eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"

# Cloud access keys
gh pr diff <N> | grep -E "^\+.*\bAKIA[0-9A-Z]{16}\b"
gh pr diff <N> | grep -iE "^\+.*aws_secret_access_key[\"']?[ ]*[:=]"

# GitHub tokens
gh pr diff <N> | grep -E "^\+.*\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b"

# Slack tokens
gh pr diff <N> | grep -E "^\+.*\bxox[bpoa]-[A-Za-z0-9-]{10,}\b"

# Long single-line base64 blobs
gh pr diff <N> | grep -E "^\+" | awk 'length > 520 && /^[+][A-Za-z0-9+/=]{500,}$/'
```

| hit | verdict |
|---|---|
| `BEGIN PRIVATE KEY` | FAIL |
| a `.key` / `.pem` / `.p12` / `.pfx` file | FAIL until inspected; PASS only if it is verified public material |
| a `.env*` / `.envrc` file added | FAIL until inspected; FAIL if it holds non-placeholder values |
| a JWT with a real payload (decode it, check `exp` and `sub`) | FAIL |
| a cloud access key | FAIL — assume it is live |
| a GitHub or Slack token | FAIL — assume it is live |
| a base64 blob over 500 characters | WARN, look at it (a legitimate fixture, or an embedded certificate?) |
| a generic key/secret assignment with a concrete value | check each hit by hand |

Placeholders (`${VAR}`, `<REPLACE>`, `CHANGE_ME_*`, `example`) pass. Concrete
strings fail.

Severity in the record is a hypothesis. Precedent: a hit was filed as "harmless
junk" and turned out to be a fully privileged key with a year left on it.

### 6. Oversized files (debug-dump suspicion)

```bash
gh pr view <N> --json files --jq '.files[] | select(.additions > 500) | "  \(.additions)+ \(.path)"'
```

For each: look at the first ten lines. If it reads as natural-language output and
`git grep -l "<filename>"` returns nothing, nobody references it, it is a debug
dump, **FAIL**. A generated lockfile, a data catalog, or a referenced fixture is
**PASS**.

---

## C. Architecture checks

### 7. Branch dependency

```bash
git fetch origin
for other in $(gh pr list --state open --json headRefName --jq '.[].headRefName'); do
  if [ "$other" != "<head-of-this-PR>" ]; then
    git merge-base --is-ancestor "origin/$other" "origin/<head-of-this-PR>" 2>/dev/null \
      && echo "WARN: $other is contained in this PR, merging will auto-close it"
  fi
done
```

Any auto-close warning -> **WARN**. Decide with the user: an intentional bundle, or
rebuild the branch onto a clean base.

### 8. Merge target sanity

```bash
gh pr view <N> --json baseRefName
```

If the repository convention is one base and this request targets another ->
**WARN**: confirm it is intentional.

### 9. Migration and infrastructure spot-check

For each `.sql` migration in the request:
- a bare `DROP CONSTRAINT` + `ADD CONSTRAINT` against a populated table -> it must
  be `ADD CONSTRAINT ... NOT VALID` (instant) followed by `VALIDATE CONSTRAINT`
  (no hard lock);
- a bare `CREATE INDEX` -> must be `CREATE INDEX CONCURRENTLY` on production tables;
- `DROP TABLE` / `TRUNCATE` with no explicit comment saying destruction is intended -> confirm with the user;
- role and grant changes -> confirm there are negative tests asserting access is denied.

Check the **outgoing** foreign keys too: dropping a child table takes a heavy
lock on the parent. That nearly froze a users table once.

For migrations written in code rather than SQL, read the statements inside the
migrate method and apply the same rules.

For each compose file, Dockerfile or reverse-proxy config change, read the diff:
- volume mounts referencing files not in the repository -> runtime breakage;
- command arguments referencing deleted files -> runtime breakage;
- environment toggles (TLS on/off, profile flags) -> consistent across every service that reads them;
- **healthcheck** changes -> the new command exists inside the image; a longer timeout means a wider window of undetected unhealthiness;
- **memory or CPU limit** reductions -> risk of the kernel killing the process under load, **WARN**;
- **network alias** changes -> name resolution in client services may break, **WARN**;
- **restart policy** changes -> confirm intentional.

---

## D. Correctness review (standing in for the missing reviewer)

**Why this section exists.** Checks 1-9 are about **hygiene**: conflicts,
secrets, file sizes, whether the description matches. Not one of them **reads the
changed code** or asks whether it is correct. While a human reviews the request,
that is fine, correctness is on them. In a project with no branch protection and
no review, there is no reviewer, and without section D the audit produces false
comfort: nine passes over wrong code.

Mandatory when the request has **no approving review** (check 3 returned WARN or FAIL).

### 10. Reading the changed code

Look at **the code only**, with comments stripped. Comments lie:

```bash
gh pr diff <N> | grep -E '^[+-]' | grep -vE '^[+-]\s*(#|//|\*)' | grep -vE '^(\+\+\+|---)'
```

Every item below needs evidence, not an opinion:

| # | question | what proves it |
|---|---|---|
| 10.1 | **Was every changed file executed?** For each: which run, which job. | run number plus the step's conclusion. A file nobody executed is unverified code |
| 10.2 | **Rarely-triggered workflows.** A scheduled job, or one triggered only on the main branch, does not fire on a pull request branch, so changes to it are **unverified**. | `gh run list --workflow <f> --branch <head>`; empty means trigger it manually on that ref |
| 10.3 | **Comment versus code.** Check every claim in an added comment against the lines next to it. | the comment quoted, and the line of code |
| 10.4 | **Expressions are evaluated, not just parsed.** Conditions, references, names with dashes. | the actual step output in the log, not a guess about syntax |
| 10.5 | **New shell in CI — does it fail closed?** An empty variable, a missing secret, a failed command must produce a loud failure, not a quiet degradation. | `set -euo pipefail`, an explicit check, and a run |
| 10.6 | **Executable artifacts** (jars, shared objects, binaries, wrapper scripts) — is the provenance independently verified? | a checksum against the upstream publication, or regeneration with a trusted tool |
| 10.7 | **Is the same fix needed in other repositories?** A class of problem rarely lives in one place. | one command measuring across every repository in the family |
| 10.8 | **A job that can never pass** (no runner, no permissions, no quota) — is it explicitly disabled, or being fixed? | a permanently red check stops being a signal; leaving it silently is not allowed |
| 10.9 | **Do the artifact and the documents describe the HEAD**, or the commit they were written on? Evidence files, the request description, the tracker — all of it ages with every new commit | pull the artifact out of the **running** container and find a marker of the last commit inside it; check the numbers in the documents against git |
| 10.10 | **Silent failure.** Every added catch, error branch, fallback, default-on-error and optional-chain — does it hide a failure? | the handler quoted, plus answers to the four questions below |

**10.10 is the most expensive disease there is.** A loud failure is visible
immediately; a quiet one lives for months. Precedents: a nightly cleanup job that
deleted nothing, ever, because it selected on status values that did not exist in
the enum, an account-deletion endpoint answering `204` over a path that had not
run, a documented ban on fallback methods in a deletion path, because a fallback
substitutes the result, the wipe returns an invented zero and the read-back an
empty list, and the deletion closes over live rows.

Four questions per handler, each answered with a quote from the code:

1. **What does it catch beyond what you expect?** Name the OTHER failures this
   handler will swallow. A broad catch hides unrelated errors and makes debugging
   impossible.
2. **Will a human learn about the failure?** Separately: will the **calling code**?
   A handler that logs and continues is a silent failure, log or no log.
3. **Does the fallback substitute the result?** A default value, an empty list, a
   zero, a mock instead of a real call, that is an answer of "fine" over work that
   did not happen. A fallback is acceptable only when it was **asked for** and
   written into a decision.
4. **Should the failure travel further up?** Swallowed here, it never reaches the
   code that knows how to handle it, and it skips resource cleanup.

**Verdict:** FAIL if the answer to 2 is "no", or the answer to 3 is "yes" and the
substitution is not recorded in a decision. An empty catch is FAIL, always.

Adapted from `silent-failure-hunter` in Anthropic's official `pr-review-toolkit`
plugin. The plugin itself was not installed: it expects logging and telemetry
infrastructure that this project does not have, and without it would fail
everything.

**10.9 exists because this class of error passed through THREE audit rounds of
one pull request in a row**, wearing a new disguise each time: the image was built
two minutes after the first of three commits, the tracker described a fix through
a method the same branch had deleted, the end-to-end check was run on the
previous commit. One command answers it, and it costs a whole round when skipped:

```bash
docker cp <container>:/app/app.jar . && unzip -p app.jar '<path/to/Changed.class>' | strings | grep '<marker from the last commit>'
```

The cause is not carelessness, it is the order of work: edit code -> write
documents -> edit again -> documents are now stale. The order that removes it: all
code in one pass, then freeze, then build and verify on the frozen head, then all
documents at once, and only then the audit. If the audit demands a code change,
the cycle starts over, including rebuilding the artifact.

**Verdict:** FAIL on any "not verified" in 10.1-10.2, on any discrepancy in
10.3-10.6, and on any discrepancy in 10.9. WARN on 10.7-10.8 if what was found
became a tracker entry.

**The honesty boundary.** If you wrote this pull request, section D is the
author checking their own work, the weakest form of review, since the blind spots
that produced the code also hide its defects. Say that to the user plainly rather
than dressing it up. The compensation is check 11.

---

## E. Compensating for the missing reviewer

**Why section E.** Sections A-D are what an author can check alone. But in a
project where the assistant writes the code, the assistant audits it, and the
user cannot review it, self-check is the only control there is. Section E builds
what is missing: independence (11), honesty about coverage (12), reversibility
(13), and a decision the user can actually make **without reading code** (14).

Mandatory when there is no approving review. "The change is small" is not a reason
to skip it: the cost of being wrong is set by what breaks, not by the diff size.

### 11. An independent lens (adversarial)

The code is looked at by someone who did not write it. Invoke `agent-spec` first.

- Classify by cost of error. **Irrecoverable** (security, migrations, architecture,
  closing a phase, anything that runs with elevated privileges) ⇒ a single agent is
  **forbidden**: three to five disjoint lenses, plus a layer whose job is to
  **refute** their verdicts.
- Define the lenses by failure mode, not by file: supply chain, logical
  correctness, what breaks in six months (an upgrade, a second developer, a
  changed environment), consistency with the project's recorded decisions.
- Tell the sceptics to **refute**, not to confirm, and to lean towards "refuted"
  when in doubt.
- **You synthesize, not an agent.** Accept verdicts selectively, by checking them.
  An agent that removed a problem from view is more dangerous than one that
  invented a problem.

Verdict: FAIL if most lenses find the change wrong or dangerous. WARN if they disagree.

#### Writing the prompt for a lens

Six mandatory blocks (`agent-prompt-block.sh` requires them or the call is rejected):

1. **Context**: what you have established and verified yourself, what counts as
   fact, what the execution privileges and the threat model are. Not "look at this
   pull request" but "I am testing the hypothesis that this protection holds".
2. **One narrow disjoint area**: one lens, one subject. Overlapping areas give you
   four retellings of the same thing instead of four different views.
3. **Output format**: a hard schema: a one-word verdict, a table with a row
   ceiling, a list with an item ceiling, a summary of fixed length. Without a
   schema you get loose prose.
4. **Prohibitions**: what not to touch (the other lenses' areas), plus "do not
   propose fixes, findings only" and "change nothing on disk".
5. **Permission to not know**: "NOT_FOUND and where you searched; do not guess".
6. **Verify before citing**: "open every line yourself", "confirm tool behaviour
   from the source or an experiment, not from memory".

**The hook matches literal words, not meaning.** Phrasings that are correct in
spirit will still get the call blocked. Use these literally: `final:` /
`output format` / `summary in N lines`, `do not` / `out of scope`, `NOT_FOUND` /
`do not guess`.

**Model and effort are two different settings, and the second is easy to miss.**
`agent-spec` requires both the top model and a high effort level for irrecoverable
work. The `Agent` tool **cannot set effort**; it is inherited from the session. It can
be set explicitly through `Workflow`. Hence the rule: if the lenses ran through
`Agent`, write it honestly in the report, "effort inherited from the session, not
set", and do not claim the work was checked at maximum depth.

**The acceptance gate is mandatory** (`agent-spec` step 4): an answer shorter
than expected, zero line references, hedged phrasing, NOT_FOUND where material
obviously exists, internal contradictions. Two or more signals mean the lens did
not work. For irrecoverable work, **retrying the same configuration is pointless**
— raise the effort, add lenses, ask a human, or do it yourself.

Order matters, and so does not panicking early: wait for the answers, run the
gate, and re-launch **on an observed signal**, not "just in case". Otherwise you
double the spend with no evidence the first round was bad.

### 12. What could NOT be verified

A mandatory section of the report. List **by name**:

- code paths that no run executed;
- claims taken on trust (a version, the behaviour of an external service, "it should work");
- checks deferred until a scheduled trigger fires or a missing environment appears;
- values left without a clean measurement.

**Without this section a wall of PASS reads as "everything was checked", and
that is a lie by omission, the most expensive kind.** An audit with no
list-of-unverified is not finished.

### 13. Rollback

Record **before** the merge, in the chat and in the report:

```bash
git rev-parse origin/<base>          # the SHA to come back to
```

And the reversibility class:

| class | what it means |
|---|---|
| **reversible** | a revert restores the state in minutes, no side effects |
| **reversible with recovery** | needs a data rollback, a key rotation, an image rebuild |
| **irreversible** | a migration on a populated table, deleted data, a published secret, an external call |

Irreversible requires **explicit** user consent with the cost of error named, not
a general "go ahead".

### 14. A summary for the user, with no code in it

**Plain language is a requirement, not a nicety.** If the user is not a
programmer, a summary they cannot read is useless in its entirety, however correct
every word of it is. This needs a check rather than good intentions: by default
the report drifts into jargon.

Rules:
- no file names, no CI job names, no run numbers, no flags, those belong in the table above;
- no unexplained technical terms. If a term is needed, explain it first and put the term in brackets after;
- every sentence answers "what does this mean for me", not "what happened in the system";
- an analogy beats precision where the precision is not checkable by the reader anyway;
- **self-check before sending:** read it as someone who does not know what a
  version control system is. If one sentence is unclear, rewrite it, do not add a footnote.

Four answers. This is what the user can actually judge:

1. **What changes for a person using the product.** If the answer is "nothing", say
   so plainly, and say why the merge is happening (infrastructure, debt, groundwork).
2. **What new capabilities and risks appeared.** List everything in the diff that:
   reaches the network, reads or creates secrets, gains new permissions, deletes
   data, adds an executable binary, runs on a schedule or a trigger.
3. **Did the work sprawl?** Compare what is in the request against what was asked
   for. Growth can be justified, but **scope is the user's decision**, and they
   should hear about it before the merge, not after.
4. **What breaks if this is wrong, and would we notice?** Separately: notice
   **immediately** (a red run), **late** (next quarter, next release), or **never**.

Verdict: FAIL if the answer to 4 is "never" and nothing is in place to change that.

## Output

One audit table, with the request identified in the header:

```
PR: owner/repo#N, "<title>"
Base: <baseRef> | Head: <headRef> (sha: <short>)
Round: <k> of 5
```

| # | group | check | verdict | detail |
|---|---|---|---|---|
| 1 | State | Conflicts (mergeable) | PASS/FAIL/WARN | _mergeable + mergeStateStatus_ |
| 2 | State | Force-push since review | PASS/WARN | _last commit vs last review_ |
| 3 | State | Review decision | PASS/FAIL/WARN | _APPROVED / CHANGES_REQUESTED / null_ |
| 4 | Content | Description vs reality | PASS/FAIL/WARN | _mismatch / missing test plan_ |
| 5 | Content | Secret scan | PASS/FAIL | _hits per category_ |
| 6 | Content | Oversized files | PASS/FAIL | _suspect files_ |
| 7 | Arch | Branch dependency | PASS/WARN | _requests that would auto-close_ |
| 8 | Arch | Merge target | PASS/WARN | _base sanity_ |
| 9 | Arch | Migration / infra | PASS/FAIL | _broken patterns_ |
| 10 | Correctness | Reading the changed code (D) | PASS/FAIL/WARN/n-a | _mandatory without an approving review_ |
| 11 | Compensation | Independent lens | PASS/FAIL/WARN/n-a | _how many lenses, how many refuted_ |
| 12 | Compensation | What could NOT be verified | list | _by name; an empty list needs justification_ |
| 13 | Compensation | Rollback | SHA + class | _reversible / with recovery / irreversible_ |
| 14 | Compensation | Summary for the user | 4 answers | _what changes, new powers and risks, scope sprawl, would we notice_ |

## After the audit

**The marker's condition is COMPLETED TRIAGE, not the absence of findings.**
This used to say "all PASS, no FAIL, no WARN", and that was the only mechanical
consequence of the entire skill: no marker while a single finding remained. The
rule "the audit is over when every finding has a decision" was written into the
preamble while the valve stayed as it was, which is how a pull request sat green
and unmerged for two days.

**Write the marker when BOTH hold:**

- **every** finding has a decision, it blocks, or it goes to the tracker;
- none of them fell into the four blocking classes: **regression**, **false
  claim** in code or a document, **irreversible harm** to a person or their data, **breaking the law**.

Findings of the kind "the check doesn't catch everything", "coverage is partial",
"could be stricter", "the gap predates this change", "the defect is in someone
else's area" — **go to the tracker, the marker is written, the merge proceeds.**

**Then:**

1. Write the marker file:
   ```bash
   HEAD_SHA=$(gh pr view <N> --json headRefOid --jq '.headRefOid' | cut -c1-8)
   OWNER=$(gh pr view <N> --json url --jq '.url' | sed -E 's|https://github.com/([^/]+)/([^/]+)/.*|\1|')
   REPO=$(gh pr view <N> --json url --jq '.url' | sed -E 's|https://github.com/([^/]+)/([^/]+)/.*|\2|')
   MARKER="/tmp/pre-merge-audit-${OWNER}-${REPO}-${N}-${HEAD_SHA}.ok"
   date -u +"%Y-%m-%dT%H:%M:%SZ" > "$MARKER"
   ```
2. Recommend a merge method:
   - a plain merge for a multi-commit branch where the individual commits carry
     value (review history, bisect points);
   - a squash when the commits are work-in-progress noise;
   - a rebase when linear history is the repository convention and every commit is
     self-contained and green.
3. Merge. **A separate permission to merge is not required**, that was settled by
   policy. The user is asked in exactly four cases: product policy, an
   irreversible action, a permission only they can grant, a severity dispute with
   an asymmetric cost.

**A finding OUTSIDE the four classes** (what used to be a WARN): one line in the
tracker, write the marker, merge. Asking the user to sign off each one is what
turned their attention into the release valve.

**A finding INSIDE the four classes** (what used to be a FAIL): no marker, fix it.
Then re-run the **triage**, not the whole audit: the next round covers only what
was repaired.

**Sign the rule is being broken:** a third audit round on one piece of work
while the production behaviour did not change between rounds.

## Marker file semantics (for downstream hooks)

Format: `/tmp/pre-merge-audit-<owner>-<repo>-<PR#>-<head-sha-short>.ok`
Content: an ISO-8601 UTC timestamp.

Downstream hooks read it to:
- recognise a fresh audit (under 24 hours) whose `<head-sha-short>` still matches `gh pr view --json headRefOid`;
- invalidate it when a force-push changed the head after the audit (the filename no longer matches, so a re-audit is needed);
- answer "when did we audit request X", `ls -la /tmp/pre-merge-audit-*-<PR>-*.ok`.
