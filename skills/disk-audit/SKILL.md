---
name: disk-audit
description: "Deep review of disk usage on a development server - four parallel read-only agents by zone (docker, tmp and worktrees, repositories, system caches), synthesized into one table of candidates, with deletion only after each verdict has been checked by hand. Use when the disk is over 80% full, when builds fail with no space left on device, or once a quarter as maintenance. Does not replace a scheduled cleanup job: that one removes the routine, this one finds what is not in its patterns."
---

# disk-audit — reviewing the disk

## When to run

- the disk is over 80% (`df -h /`), or
- a build or test failed with `ENOSPC`, `No space left on device`, or a bus error in the linker, or
- quarterly maintenance.

**First check whether your scheduled cleanup already did the work:** read its log.
If it ran and failed with "disk over 85%", the routine was removed and something
outside its patterns ate the space. That is the case for a full review.

## Why not just `du | sort | rm`

From the session that produced this skill:

- **The biggest consumer was innocent.** A backup directory held 76G, 44% of the
  disk, and looked like a textbook leak. Rotation was working; the 30-day window
  was a deliberate decision tied to a legal data-retention requirement. Deleting
  it "as junk" would have broken compliance.
- **The culprit was me.** 29G of build output from my own runs that session, 15%
  of the disk, out of nowhere, in an afternoon.
- **Running out of space silently corrupted a database backup**: 57MB where 600MB
  was expected. A full disk is not only about space; it breaks the things that
  quietly depend on having some.

Hence the rules.

## Rules

1. **Agents inventory, you delete.** An agent's mistake in reconnaissance is
   visible when you check it. An agent's mistake with `rm` is not undoable. Never
   give an agent permission to delete.
2. **An agent's verdict is a hypothesis, not an instruction.** Before deleting,
   check it yourself: what is the thing, who wrote it, is anything uncommitted.
3. **`SAFE` only for what one command recreates.** Tool caches (npm, gradle, maven,
   cargo) are always `ASK`: deleting them is safe for the data and expensive for
   the next build. Dumps and data are always `ASK`, however old.
4. **Find out why it exists before removing it.** If there is a policy behind it
   (retention, a legal requirement, groundwork for something unwritten), it is not
   junk. Check the decisions log, not the file name.
5. **After cleaning, prove the stack is alive.** Not "the command succeeded", but:
   containers up, the database answers a query, the service returns 200.

## Procedure

### 1. The view from above (yourself, one command)

```bash
df -h / ; df -i / ; du -sh /* 2>/dev/null | sort -rh | head -10
```

That last part is the step that found the 76G directory. Without it the agents
faithfully inventory the zones you named, and the biggest consumer stays invisible:
**give them the zones from this output, not the zones from your head.**

### 2. Four agents, parallel, read-only

Mid-tier model: reconnaissance is recoverable, your own check catches the error.
Fan-out of four is the recoverable limit in `agent-spec`.

Zones, disjoint or they duplicate each other's work:
1. **Docker**: `system df -v`, dangling images, stopped containers, orphaned volumes, `builder du`, bloated container logs.
2. **/tmp and worktrees**: large directories, build output, orphaned worktrees (check against `git worktree list`, not against the directory name).
3. **Repositories**: build output, `node_modules`, `.next`, `build/`, virtualenvs; always `git status --short` before any verdict.
4. **System zones and caches**: `/var/log`, journal, package manager caches, language toolchain caches, `~/.cache`, `/usr`, `/opt`, any file over 500M.

**Plus any zone from step 1 that is not in this list**: that is the one you would
otherwise miss.

Each prompt carries the six blocks (`agent-spec` step 3; the hook will reject it
otherwise) and stays under 4000 characters:
- **Context:** the numbers from step 1, what has already been cleaned, what is known.
- **Zone:** exactly one, named; list the other three as "do not touch".
- **Deliverable:** two tables. A: `path | size | what it is | verdict SAFE/ASK/KEEP | reasoning`. B: `zone | total | reclaimable as SAFE`.
- **Out of scope:** "DELETE NOTHING", list the forbidden commands by name (`rm`, `prune`, any `clean` subcommand, log vacuuming), "do not propose a plan".
- **Permission to not know:** "if a command failed, write NOT_FOUND and which command; do not invent numbers".
- **Verify:** "every number comes from real command output".

**Always list the untouchables by name**: the agent does not know your stack:
live containers, volumes holding database data, active worktrees, containers this
session is using.

### 3. Synthesis (yourself)

Collect the tables. Run the acceptance gate (`agent-spec` step 4): no numbers,
everything NOT_FOUND, generic phrasing -> one retry with an upgrade.

Clean in order of "cheapest to get back":
1. your own build output;
2. docker: build cache, dangling images, orphaned volumes;
3. rotated logs (`.log.1`, `*.gz`, closed, nothing is writing to them);
4. junk in `/tmp`.

`ASK` items go to the user as a list with numbers. You do not decide those.

### 4. Verification afterwards (mandatory)

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -c Up
# a real query against the database — row count of a table you know
# a health endpoint on a service — expect 200
```

Expected: containers up, the row count unchanged, health 200.

## Fill this in for your own setup

List what your scheduled jobs already handle, so the audit does not duplicate
them, and, more importantly, so the gap between "automated" and "not automated"
is written down. That gap is where the space goes.

| what | by what | when |
|---|---|---|
| docker images, containers, cache | | |
| database backups: age and frequency | | |
| build output, tmp junk, orphaned worktrees | | |
| log rotation | | |

**Not automated (this is where to look):** tool caches, the system journal,
one-off dumps, files belonging to other projects.

## A hole worth naming

If nothing exports disk metrics, nothing alerts on filling up, however much
monitoring you have running. Then the only signal is your weekly cleanup job
failing, which is a signal once a week. That is weak: a disk can reach 100% and
corrupt a backup between two runs of it. The real fix is a metrics exporter plus
an alert rule, roughly ten lines of configuration. It beats any amount of
cleaning, because cleaning treats the symptom.
