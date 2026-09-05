# Hooks

Fifteen scripts. They live in `~/.claude/hooks/` and are wired up in `~/.claude/settings.json`.

Every one of them exits 0 when anything unexpected happens. A hook that breaks your session gets deleted the same day, and then you have no hook at all, so failing open is the only sane default.

## Injecting context

These put something in front of the model at the moment it decides, instead of at the top of a context it has long since drifted away from.

| hook | event | injects |
|---|---|---|
| `turn-rules.sh` | UserPromptSubmit | The four release blockers. Every turn. This is the one carrying the load. |
| `claude-md-refresh.sh` | UserPromptSubmit | Section headers from the universal and project `CLAUDE.md`, on turn 1 and every twentieth after that. |
| `project-version-snapshot.sh` | UserPromptSubmit | Once per session: the versions actually in your manifests, and the gap between today and your model's cutoff. Put the cutoff in `~/.claude/discipline/model-cutoff`. |
| `agent-spec-reminder.sh` | PreToolUse on Agent | The routing checklist, right as a subagent is about to spawn. |
| `agent-verify-reminder.sh` | PostToolUse on Agent | How to read what came back. Did it answer your questions, or questions near yours? |
| `merge-gate-reminder.sh` | PreToolUse on Bash | On `gh pr merge`, the four questions. Always lets the merge through. The comment at the top of that file is the most important text in this repository. |

## Warning

One specific way of being confidently wrong each. None of them block.

| hook | fires on | catches |
|---|---|---|
| `numeric-claim-warn.sh` | writing a `.md`, or a commit message | Counted claims. "17 tests", "4 files", written from memory rather than from the command that produces the number. |
| `stale-config-warn.sh` | a launch command carrying env vars | Variable names read out of `.env.example` or the README. Those drift on every rename and nothing fails when they do. |
| `code-commit-e2e.sh` | `git commit` with code staged | A message with no sign the change was ever executed. Docs and refactor commits are ignored. |
| `test-discipline-check.sh` | writing a test file | Weakened assertions, skip annotations, swallowed exceptions, TODOs. |
| `tracker-convergence-notice.sh` | Stop | Runs your own consistency check and reports divergence. Does nothing until you configure it. |

## Blocking

Four, and each one was written after the thing it blocks actually happened.

| hook | blocks | way past it |
|---|---|---|
| `block-bad-commands.sh` | Staging the whole tree, force-pushing without a lease, skipping git hooks in either form, repointing `core.hooksPath`, destroying a guard file, interactive git | Do the thing the denial names. Every message says what. |
| `block-test-edits.sh` | Any edit to a test file | The user creates a single-use grant. The denial prints the exact command. |
| `block-guard-edits.sh` | Any edit to a hook, to `settings.json`, or to a git-hook directory | Same mechanism, separate directory. |
| `agent-prompt-block.sh` | Subagent prompts hitting one of seven anti-patterns: too fat, too many items, mixed research-and-fix framing, no output schema, no out-of-scope, no permission to say NOT_FOUND, unverified `file:line` citations | Rewrite the prompt. There is no bypass. |

### Grants

`block-test-edits.sh` and `block-guard-edits.sh` work the same way. Neither lets the edit through until a file named after the SHA-256 of the target path exists. One successful edit consumes it.

This is not ceremony. The point is that the assistant cannot create the grant for itself, because writing into the grant directories from the shell hits rule 5 of `block-bad-commands.sh`. A permission the asker can grant itself is not a permission.

The hash comes from `sha256sum`, `shasum -a 256` or `openssl dgst -sha256`, whichever exists. If none do, the hooks deny rather than continue: an empty hash would collapse every path onto one grant file, so a single permission would unlock everything.

## Configuration

Optional, all under `~/.claude/discipline/`:

| file | read by | holds |
|---|---|---|
| `model-cutoff` | `project-version-snapshot.sh` | One line, `YYYY-MM`. Without it the hook uses a built-in date and labels it as a fallback. |
| `guard-paths.txt` | `block-bad-commands.sh` | Extra shell-protected paths, one extended-regex alternative per line. |
| `guard-edit-paths.txt` | `block-guard-edits.sh` | Extra edit-protected paths, one glob per line. |
| `tracker.conf` | `tracker-convergence-notice.sh` | `WORKSPACE=` and `CHECK=`. No file, no hook. |

Put your own check scripts in both guard lists.

## Turning one off

Remove its entry from `~/.claude/settings.json` and restart.

Measure before you do. One rule was dropped from `block-bad-commands.sh` on exactly that basis, after it turned out to block one of six ways to read the same file while fighting the harness for the privilege. The removal note at the top of that file is the shape of argument to make.

Everything at once:

```bash
mv ~/.claude/settings.json ~/.claude/settings.json.disabled
```

## Debugging

Hooks read a JSON event on stdin, so you can feed them one by hand:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | ~/.claude/hooks/block-bad-commands.sh
```

A blocker answers with `permissionDecision: "deny"`. An injector answers with `additionalContext`. Silence and exit 0 means the hook decided this was not its case.

To see what a hook actually receives, put this at the top of it. The `tee` matters, since the hook consumes stdin:

```sh
tee -a /tmp/claude-hook-debug.log |
```

## Writing your own

1. It solves something that actually recurred. Not something you can imagine recurring.
2. Under a second for PreToolUse, under five for PostToolUse.
3. Narrow matcher. Silent on everything irrelevant.
4. Three to five lines of output. Longer than that and it gets skimmed.
5. Fail open, always. Exit 0 on any uncertainty.
6. No side effects beyond stdout, stderr and the exit code.
7. If it blocks, the denial has to name the correct path. A blocker that only says no gets routed around within a week.

One more, learned the hard way. Several rules in `block-bad-commands.sh` match on literal substrings, so writing that file through a shell heredoc trips its own rules. Edit it with a file tool.
