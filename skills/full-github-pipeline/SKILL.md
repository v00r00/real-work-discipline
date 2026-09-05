---
name: full-github-pipeline
description: "End-to-end orchestrator from uncommitted local code to merged across one or many repositories. Sequences multi-repo-status (inventory and commit grouping), commits, push, opening the pull request, pre-merge-audit, merge and post-merge cleanup. Stops at every decision point for explicit user confirmation. Use when there is a backlog spanning the whole commit-to-merge cycle that needs doing properly without skipping steps."
---

# Full GitHub pipeline

Run this skill when:
- There is uncommitted or unpushed work in one or more repositories and you want
  to take it from "in the working tree" to "merged" without skipping steps.
- After a long coding session, the results need publishing properly.

Do NOT use for:
- A single pull request you have already opened, invoke `pre-merge-audit` directly.
- Inventory with no intent to merge today, invoke `multi-repo-status` directly.

## What it does

Eight phases. Each ends either in a hand-off to a sub-skill or in a confirmation
gate. Never advance past a gate without an explicit "ok" / "merge" / equivalent.

## Phase 1 — Inventory

Invoke `multi-repo-status` for the repositories in scope. Show the table. WAIT
for the user to confirm the scope and approve the proposed commit grouping.

## Phase 2 — Commit hygiene

For each repository with uncommitted work, in the order proposed by phase 1:
- stage the files of one group at a time, by name, never the whole tree;
- one commit per group;
- subject line 70 characters or fewer; the body explains WHY, not what, the diff
  already says what;
- add whatever trailer the project convention requires.

## Phase 3 — Push

For each branch with new commits:
- no upstream -> `git push -u origin <branch>`;
- push blocked by a hook -> READ the hook's message; it usually states the right
  path. Do not skip hook verification without explicit permission from the user;
- if the branch is the shared integration branch and you meant to be on a feature
  branch, you committed in the wrong place. Stop and fix it before pushing.

## Phase 4 — Pre-PR analysis

Before opening anything, check the topology:

```bash
git rev-list --count <target>..<branch>   # ahead
git rev-list --count <branch>..<target>   # behind (>0 means rebase first)

gh pr list --head <branch> --state all    # does a PR already exist?

# Does this branch entirely contain another open feature branch?
git fetch origin
for other in $(gh pr list --state open --json headRefName --jq '.[].headRefName'); do
  [ "$other" != "<this-branch>" ] && git merge-base --is-ancestor "origin/$other" "<this-branch>" \
    && echo "DEP: $other is contained in <this-branch>, its PR will auto-close when this one merges"
done
```

`behind > 0` -> rebase onto `origin/<target>` before continuing.
A dependency warning -> decide with the user: an intentional bundle (proceed), or
rebuild this branch by cherry-picking to exclude the other pull request's commits.

## Phase 5 — Open the pull request

```bash
gh pr create --base <target> --head <branch> --title "..." --body "..."
```

- Title under 70 characters.
- The body must list every significant theme, derived from
  `git log <target>..<branch> --oneline` — NOT from memory. Include the commit
  count, ahead/behind against the base, and a `## Test plan` section even if the
  project has no CI: it lists what a human should verify by hand.

Immediately after creation, self-check:
```bash
gh pr view <N> --json files --jq '.files[].path'
```
If the files exceed what the body claims, rewrite the body with `gh pr edit`
BEFORE anything else. A description that does not match the contents is a false
claim in a document, one of the four things that actually block a release.

## Phase 6 — Pre-merge audit

Invoke `pre-merge-audit <N>`. WAIT for the audit table.

A **FAIL** stops the pipeline: apply the cleanup pattern below, then re-run the
audit, but only over what was fixed, not the whole thing.

A **WARN** is triaged, not escalated: if it is not one of the four blocking
classes, it becomes a tracker entry and the merge proceeds.

## Phase 7 — Merge

- Show the user the audit summary and the recommended merge method.
- `gh pr merge <N> --merge` (or `--squash` where the individual commits carry no value).
- Verify: `gh pr view <N> --json state,mergedAt,mergeCommit`, the state must be `MERGED`.
- For dependent pull requests that should have auto-closed, confirm they did.

## Phase 8 — Cleanup

For each merged feature branch:
```bash
git push origin --delete <branch>
git branch -D <branch>
```

Sync the local target:
```bash
git checkout <target>
git fetch origin <target>
echo "BACKUP local <target> SHA: $(git rev-parse <target>)"   # for the record, before the reset
git reset --hard origin/<target>
```

Final state per repository:
```bash
echo "$(basename $repo): branch=$(git branch --show-current), uncommitted=$(git status --short | grep -v '^??' | wc -l), unpushed=$(git log --oneline @{u}.. | wc -l)"
```
Expected: on the target branch, nothing uncommitted, nothing unpushed. Anything
else, investigate; do not declare it done.

## Cleanup pattern (when the audit fails in phase 6)

The rebase-edit-amend cycle, for a feature branch you own:

```bash
# 1. Record the SHA to go back to, before anything destructive
echo "BACKUP: $(git rev-parse origin/<branch>)"

# 2. Rebase to edit one specific commit (non-interactively)
GIT_SEQUENCE_EDITOR='sed -i "s/^pick <SHA-prefix>/edit <SHA-prefix>/"' git rebase --interactive <base>

# 3. At the stop: fix the problem
git rm <bad-files>            # or an Edit for in-file changes
git commit --amend --no-edit  # or with a new message if the old one now lies

# 4. Continue
git rebase --continue

# 5. Force-push with the safety net (refuses if the remote moved)
git push --force-with-lease origin <branch>

# 6. Rebase anything stacked on this branch
git checkout <stacked-branch>
git rebase --onto "origin/<branch>" <old-tip-SHA> <stacked-branch>
git push --force-with-lease origin <stacked-branch>
```

Never force-push without a lease. Never force-push a shared branch. Never skip
the phase-6 re-run after cleanup, fixes introduce their own problems.

## Final report

One short paragraph:

> N pull requests merged across X repositories. N feature branches deleted. N
> issues caught and fixed in the audit (list them briefly). N findings filed as
> tracker entries rather than fixed (name them). All repositories clean, target
> branch synced.

No celebration. The findings you did NOT fix are the part worth naming, silently
closing a finding is the failure mode this line exists to prevent.
