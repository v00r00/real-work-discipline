# real-work-discipline

Hooks and skills for Claude Code. They exist to solve one problem: work that never finishes.

Wrong code is not the problem. Wrong code is loud, it shows up in a diff, and reverting it takes a minute. The expensive failure is quieter than that. Any check can be made stricter. Any guard has some mutation it misses. So "done" slowly turns into "no findings left", and findings never run out. The plan grows faster than you can execute it, and nothing ever ships.

This is what came out of fighting that for several months on a real codebase. Fifteen hooks, nine skills, one rules file.

Nothing here was designed in the abstract. Every rule was added after something went wrong, and the header of each hook says what. Where a hook looks paranoid, read the comment before deleting it. Where it looks lax, read the comment too, because two of them used to be strict and were deliberately loosened.

## The rule everything else hangs off

A hook prints this before every turn:

> Four kinds of finding stop a release: a regression, a false claim in code or a document, irreversible harm to a person or their data, breaking the law. Everything else is a tracker entry and the work continues.

And the one that makes the first one hold:

> "Done" is one sentence, written before the work starts. It does not change. Anything found along the way goes in the tracker and does not extend the current work.

Everything else in here is those two applied to specific moments: merging, spawning subagents, editing tests, citing code, cleaning a disk.

## Install

You need `jq`. The skill validator also wants `python3` with `pyyaml`. Grants are keyed by a SHA-256 of the file path, which comes from `sha256sum`, `shasum` or `openssl`, whichever you have.

```bash
git clone https://github.com/v00r00/real-work-discipline.git
cd real-work-discipline
./install.sh --dry-run
./install.sh
```

Files go to `~/.claude`, or to `$CLAUDE_CONFIG_DIR` if you set it. Paths inside `settings.json` are absolute and resolved at install time, so it does not matter where your home directory lives.

Your `settings.json` is merged, not replaced. Model, theme, permissions and your own hooks survive. Anything overwritten is copied to `~/.claude/backups/` first and the path is printed at the end. Running the installer again is safe: it strips its own previous entries before adding them back, so hook counts stay put.

If you already have a `~/.claude/CLAUDE.md`, it is left alone. If you do not, `CLAUDE.md.example` is copied into place.

Restart your session afterwards. `/hooks` shows what loaded.

## Hooks

Full list with the details: [`hooks/README.md`](hooks/README.md).

Six of them inject context. They put a rule in front of the model at the moment it makes a decision, rather than at the top of a context it drifted away from twenty turns ago. The four blockers on every turn. `CLAUDE.md` headers again every twentieth turn. Your manifest versions once per session, with how far that is from your model's cutoff. The subagent routing checklist a beat before an agent spawns.

Five warn about one specific way of being confidently wrong each. A number written from memory instead of from the command that produces it. Environment variable names taken from `.env.example`, which drifts silently, instead of from the code that reads them. Code committed with nothing in the message suggesting it was ever run. A test file that just grew a skip annotation.

Four block outright:

- `block-bad-commands.sh` catches staging the whole tree, force-pushing without a lease, skipping git hooks in either the long or the short form, repointing `core.hooksPath`, and deleting a guard.
- `block-test-edits.sh` stops any edit to a test until a human grants it, once, for that file.
- `block-guard-edits.sh` does the same for the hooks themselves. It was added after a probe showed the guards were protected from the shell and completely open to the editor.
- `agent-prompt-block.sh` rejects a subagent prompt that is too fat, has no output schema, no out-of-scope list, or no permission to answer "not found".

That last one has no override flag, and that is deliberate. It fires precisely when nobody feels like being careful.

The two grant hooks share a trick worth stealing. The assistant cannot create its own grant: writing into the grant directory from the shell runs into rule 5 of `block-bad-commands.sh`. A permission you can hand yourself is not a permission.

## Skills

| skill | for |
|---|---|
| `define-done` | Write "done" to a file before the first edit. Cut the work into steps of a few minutes. Keep a log that survives a context compaction. |
| `grill-me` | Ask questions in rounds down the decision tree until a "done" sentence can honestly be written. Whole frontier per round, with your own recommendation on every question. |
| `agent-spec` | Before any subagent: classify by cost of error, pick the model, structure the prompt, then run an acceptance gate on what comes back. |
| `pre-merge-audit` | Fourteen checks in cost-ordered tiers, a five-round breaker, and a section for when there is no reviewer. The longest file here and the one with the most scar tissue. |
| `phase-reaudit` | Four agents with disjoint lenses over a milestone that is formally closed. |
| `verify-claims` | Walk every `file:line` in a document and check it against the file. |
| `multi-repo-status` | See what is uncommitted and unpushed across several repos before touching any of them. |
| `full-github-pipeline` | Uncommitted to merged, with gates. |
| `disk-audit` | Four read-only agents over disk zones. They inventory, you delete. |

`skills/validate-skills.sh` checks all of them against the Agent Skills spec. Claude Code parses more leniently than the spec does, so the failures it finds are ones you cannot see by reading: a colon that broke the YAML, a description 268 characters over the limit, an angle bracket.

## Read these even if you install nothing

[`hooks/merge-gate-reminder.sh`](hooks/merge-gate-reminder.sh) is a hook that used to block merges and now never blocks anything. It wanted a marker file that the audit only wrote when every check passed with no warnings, and since findings always exist, the marker never existed, so nothing merged. One pull request sat green and unmerged for two days, held up by a missing file in `/tmp`. It also failed closed on network errors, which meant it refused merges hardest at the moment it knew least.

[`hooks/tracker-convergence-notice.sh`](hooks/tracker-convergence-notice.sh) was the engine driving the whole problem. It would not let a turn end until every finding had been assigned to a piece of work. A finding had two exits: become work, or be declared not-work. Finding anything therefore meant extending the plan, every single time. The fix was a third exit.

The tier table in `skills/pre-merge-audit/SKILL.md`. One pull request went through five audit rounds. In four of them the blocking finding would have been caught by a command that takes under a second, and in all four that command was run last, after a full multi-agent pass. Cheap checks first is not an efficiency preference.

## The two audit scripts

`pre-merge-audit` runs in four tiers, cheapest first, and stops between them. Tiers three and four are instructions. The first two are programs, and they ship with the kit:

```bash
~/.claude/tools/audit-tier1.sh <PR-number>     # text, git, files. Under a second.
~/.claude/tools/audit-tier2.sh <head-sha>      # is the running stack built from this commit?
```

Tier one needs no configuration at all: mergeable state, whether the reviewed code is still the code, an empty description, secrets in the diff, oversized additions, and stale commit references inside changed documents. That last one is the check that pays for the script. A document saying "verified on abc1234" goes stale the moment the next commit lands, and nothing in CI notices.

Tier two reads `~/.claude/discipline/audit-tier2.conf` — a container name, a path to an artifact inside it, optionally a marker string. It copies the artifact out and looks for the marker. Without that file it prints SKIP and says plainly that nothing was checked, which is not the same as nothing being wrong.

Both refuse to report a clean run they did not earn. An empty diff fails. An unreadable artifact fails. Tier one opens by running its own secret patterns against a planted key, because a scanner that cannot fire in your environment says "no matches" and looks exactly like good news.

## Checking it works

```bash
./test/run-hook-tests.sh
./test/run-tier-tests.sh
```

49 cases against the installed hooks, each fed a real event on stdin. Roughly half are negative controls, cases that must be allowed through, for the reason at the top of that file: a guard that denies everything looks exactly like a guard that works.

Writing the suite immediately paid for itself. The status line was eating its own colour reset, because `printf` read the `%` in "ctx: 72%" as a format specifier and every following line stayed yellow. The README claimed five blockers when there are four. And a portable-date fix I was confident about turned out to be a bashism that dies under `/bin/sh`.

## Tuning it

Put your model's knowledge cutoff, as `YYYY-MM`, in `~/.claude/discipline/model-cutoff`. Without it the version hook falls back to a built-in date and says so in the text it injects, so a wrong number is visible rather than silent.

Add your own check scripts to `~/.claude/discipline/guard-paths.txt` and `guard-edit-paths.txt`. A checker that the thing being checked can edit is not a checker.

Point the Stop hook at your own consistency check with `~/.claude/discipline/tracker.conf`. Without that file it does nothing at all.

Before you drop a rule, measure what it catches. Before you keep one, measure that too. A rule banning shell reads of project source was in here until it went on the bench: it blocked one of six ways to read the same file, and it was fighting Claude Code's own automatic mode for the privilege. The note at the top of `block-bad-commands.sh` is what that argument looks like written down.

## Credit

The tree-and-rounds mechanic in `grill-me` comes from [mattpocock/skills](https://github.com/mattpocock/skills), MIT.

Check 10.10 in `pre-merge-audit`, the four questions to put to every error handler, is adapted from `silent-failure-hunter` in Anthropic's `pr-review-toolkit` plugin. The plugin itself expects logging and telemetry infrastructure that was not there, and without it fails everything.

`skills/validate-skills.sh` borrows its rules from `quick_validate.py` in Anthropic's `skill-creator`.

## Licence

MIT, see [LICENSE](LICENSE).
