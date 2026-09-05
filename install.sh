#!/usr/bin/env bash
# Installs the kit into your Claude Code config directory.
#
#   ./install.sh              install or update
#   ./install.sh --dry-run    show what would happen, change nothing
#
# It never overwrites anything without keeping a copy: every file it replaces is
# backed up under ~/.claude/backups/real-work-discipline-<timestamp>/, and the
# path is printed at the end.
#
# settings.json is MERGED, not replaced. Your own hooks, permissions, model and
# theme are left alone. Re-running the installer removes this kit's old hook
# entries first, so it is idempotent rather than cumulative.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_DIR/backups/real-work-discipline-$STAMP"
DRY=0

[ "${1:-}" = "--dry-run" ] && DRY=1

say()  { printf '%s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }

command -v jq >/dev/null 2>&1 || { say "ERROR: jq is required and was not found."; exit 1; }

say "Installing into: $CLAUDE_DIR"
[ "$DRY" = 1 ] && say "(dry run — nothing will be written)"
say ""

# --- backup helper --------------------------------------------------------
backed_up=0
backup_file() {
  local target="$1" rel="$2"
  [ -e "$target" ] || return 0
  if [ "$DRY" = 1 ]; then
    printf '  would back up: %s\n' "$rel"
  else
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$target" "$BACKUP/$rel"
  fi
  backed_up=1
}

# --- hooks, skills, commands ---------------------------------------------
say "hooks:"
run mkdir -p "$CLAUDE_DIR/hooks"
for f in "$SRC"/hooks/*.sh; do
  name="$(basename "$f")"
  backup_file "$CLAUDE_DIR/hooks/$name" "hooks/$name"
  run cp "$f" "$CLAUDE_DIR/hooks/$name"
  run chmod +x "$CLAUDE_DIR/hooks/$name"
  say "  $name"
done
backup_file "$CLAUDE_DIR/hooks/README.md" "hooks/README.md"
run cp "$SRC/hooks/README.md" "$CLAUDE_DIR/hooks/README.md"

say ""
say "skills:"
run mkdir -p "$CLAUDE_DIR/skills"
for d in "$SRC"/skills/*/; do
  name="$(basename "$d")"
  backup_file "$CLAUDE_DIR/skills/$name" "skills/$name"
  run mkdir -p "$CLAUDE_DIR/skills/$name"
  run cp "$d/SKILL.md" "$CLAUDE_DIR/skills/$name/SKILL.md"
  say "  $name"
done
run cp "$SRC/skills/validate-skills.sh" "$CLAUDE_DIR/skills/validate-skills.sh"
run chmod +x "$CLAUDE_DIR/skills/validate-skills.sh"

say ""
say "tools:"
run mkdir -p "$CLAUDE_DIR/tools"
for f in "$SRC"/tools/*.sh; do
  name="$(basename "$f")"
  backup_file "$CLAUDE_DIR/tools/$name" "tools/$name"
  run cp "$f" "$CLAUDE_DIR/tools/$name"
  run chmod +x "$CLAUDE_DIR/tools/$name"
  say "  $name"
done

say ""
say "commands:"
run mkdir -p "$CLAUDE_DIR/commands"
for f in "$SRC"/commands/*.md; do
  name="$(basename "$f")"
  backup_file "$CLAUDE_DIR/commands/$name" "commands/$name"
  run cp "$f" "$CLAUDE_DIR/commands/$name"
  say "  /${name%.md}"
done

# --- statusline -----------------------------------------------------------
backup_file "$CLAUDE_DIR/statusline-command.sh" "statusline-command.sh"
run cp "$SRC/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
run chmod +x "$CLAUDE_DIR/statusline-command.sh"

# --- working directories --------------------------------------------------
run mkdir -p "$CLAUDE_DIR/test-edit-grants" "$CLAUDE_DIR/guard-edit-grants" "$CLAUDE_DIR/discipline"

# --- universal CLAUDE.md --------------------------------------------------
say ""
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  say "CLAUDE.md: you already have one — left untouched."
  say "  Compare with $SRC/CLAUDE.md.example and merge by hand if you want the rules."
else
  run cp "$SRC/CLAUDE.md.example" "$CLAUDE_DIR/CLAUDE.md"
  say "CLAUDE.md: installed (you had none)."
fi

# --- settings.json --------------------------------------------------------
say ""
say "settings.json: merging"
SETTINGS="$CLAUDE_DIR/settings.json"
backup_file "$SETTINGS" "settings.json"

TPL="$(sed "s|__CLAUDE_DIR__|$CLAUDE_DIR|g" "$SRC/settings.template.json")"
EXISTING='{}'
[ -f "$SETTINGS" ] && EXISTING="$(cat "$SETTINGS")"

MERGED="$(printf '%s' "$EXISTING" | jq \
  --argjson tpl "$TPL" \
  --arg dir "$CLAUDE_DIR/hooks/" '
  # Drop any hook group that only references this kit, so re-running is
  # idempotent instead of cumulative. A group mixing your hooks with ours is
  # kept as-is and reported, because silently rewriting it would lose yours.
  def ours: [(.hooks // [])[] | .command // ""] | map(startswith($dir)) | all;
  reduce ($tpl.hooks | keys[]) as $ev (
    .;
    .hooks[$ev] = (((.hooks[$ev] // []) | map(select(ours | not))) + $tpl.hooks[$ev])
  )
  | if (.statusLine // null) == null then .statusLine = $tpl.statusLine else . end
')"

if [ "$DRY" = 1 ]; then
  say "  would write $SETTINGS"
  printf '%s' "$MERGED" | jq -e . >/dev/null && say "  (merged JSON is valid)"
else
  printf '%s\n' "$MERGED" | jq -e . >/dev/null || { say "ERROR: merged settings are not valid JSON — nothing written."; exit 1; }
  printf '%s\n' "$MERGED" > "$SETTINGS"
  say "  written"
fi

if [ -f "$SETTINGS" ] && [ "$(printf '%s' "$EXISTING" | jq -r '.statusLine // "none"')" != "none" ]; then
  say "  statusLine: you already had one — kept yours."
fi

# --- done -----------------------------------------------------------------
say ""
say "Done."
if [ "$backed_up" = 1 ] && [ "$DRY" = 0 ]; then
  say "Replaced files were backed up to: $BACKUP"
fi
say ""
say "Restart your Claude Code session for the hooks to load."
say "Then check they are live:  claude  ->  /hooks"
say ""
say "To remove: delete this kit's files from $CLAUDE_DIR/hooks and $CLAUDE_DIR/skills,"
say "and restore settings.json from the backup directory above."
