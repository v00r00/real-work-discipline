---
name: multi-repo-status
description: "Inventory uncommitted and unpushed work across several related repositories. Returns a table of branch, uncommitted, unpushed and upstream status per repo, then proposes a commit grouping by topic. Use at the start of a multi-repo session, after a context switch when the state is unclear, or before opening any pull request - to surface a branch nobody has pushed for days, and a key file accidentally staged, before they bite."
---

# Multi-repo status

Run this skill when:
- Work touches more than one related repository and the current state is unclear.
- After a context switch, when you have lost track of what is committed where.
- Before opening any pull request, to know whether the branch carries unpushed history nobody has seen.

Do NOT use for:
- A single-file edit in one known repo (just run `git status`).
- A one-off debugging session that will not produce commits.

## What it does

Walks each requested repository, reports `branch / uncommitted / unpushed /
upstream`, then for repositories with uncommitted changes scans the diff for
high-risk content (secret-suspect files, oversized blobs) and proposes a commit
grouping by topic. Stops before any staging or committing, it produces a plan,
it does not execute it.

## How to invoke

Ask the user for the **list of repositories to inventory**. If they say "all",
list the immediate subdirectories of the workspace root that contain a `.git`
directory.

For each repository:

```bash
cd <repo>
echo "=== <repo-name> ==="
echo "  branch:   $(git branch --show-current)"
echo "  upstream: $(git rev-parse --abbrev-ref @{u} 2>/dev/null || echo 'NONE, never pushed')"
echo "  unpushed: $(git log --oneline @{u}.. 2>/dev/null | wc -l)"
git status --short
```

Print one markdown table covering every repository: `repo | branch | uncommitted
| unpushed | upstream`. Highlight rows where `upstream=NONE` or `unpushed >= 10`
— that is work nobody has seen, and it is the highest-risk slice.

For each repository with uncommitted changes:

1. Run `git diff --stat HEAD` and `git diff --stat --cached`.
2. Flag:
   - `.key`, `.pem`, `.crt`, `.p12`, `.pfx` files, `secret-suspect, do not auto-include`;
   - files with more than 500 lines added, `oversized, confirm this is an intended fixture and not a debug dump`;
   - plan and doc files mixed with code files, `recommend separate commits`.

3. Propose a commit grouping per repository (aim for five commits or fewer):
   - group by topic, not by file;
   - if one file carries several topics and splitting it interactively is
     impractical, default to one commit per file;
   - show the proposed split to the user and get an explicit "ok" or revisions
     BEFORE anything is staged or committed.

## After the inventory

Hand off based on intent:
- `full-github-pipeline` if running the whole cycle (commits -> push -> PR -> merge).
- `pre-merge-audit` if a pull request already exists and needs verification before merging.
- Stop here if inventory was the goal.
