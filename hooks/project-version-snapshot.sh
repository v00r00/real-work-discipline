#!/bin/sh
# UserPromptSubmit hook. Once per session, parses the manifest files in the
# working directory and injects a snapshot of the versions actually installed,
# plus how far today is from the model's knowledge cutoff.
#
# WHY. A model states framework idioms with the confidence of its training data,
# which is a snapshot months or years old. The manifest is the only source that
# is true today. This does not make the model correct — it makes the drift
# visible, so "check the current docs" becomes an obvious move instead of an
# afterthought.
#
# Flag: /tmp/claude-version-snapshot-<session_id>.flag
#
# The cutoff below is a fallback, and the injected text says so. Put your own
# model's cutoff as a single YYYY-MM line in:
#   ~/.claude/discipline/model-cutoff
# A stated fallback is honest; a hardcoded number pretending to be your model's
# would report a drift that is simply wrong, and nothing would ever contradict it.

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
FALLBACK_CUTOFF="2026-05"

cutoff="$FALLBACK_CUTOFF"
cutoff_note=" (fallback — put your model's cutoff as YYYY-MM in $CLAUDE_DIR/discipline/model-cutoff)"
cutoff_file="$CLAUDE_DIR/discipline/model-cutoff"
if [ -f "$cutoff_file" ]; then
  configured=$(head -1 "$cutoff_file" | tr -d '[:space:]')
  case "$configured" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]) cutoff="$configured"; cutoff_note="" ;;
  esac
fi

# Strip the leading zero with parameter expansion. Two traps here, both hit:
# `date +%-m` is a GNU extension that macOS does not have, and `$((10#$m))` is a
# bashism this /bin/sh script cannot use — under dash it dies with "expecting EOF".
cutoff_year=${cutoff%-*}
cutoff_month=${cutoff#*-}
cutoff_month=${cutoff_month#0}

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"')
flag_file="/tmp/claude-version-snapshot-${session_id}.flag"

[ -f "$flag_file" ] && exit 0
touch "$flag_file"

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd="$(pwd)"

today=$(date +%Y-%m-%d)
this_year=$(date +%Y)
this_month=$(date +%m)
this_month=${this_month#0}
months_drift=$(( (this_year * 12 + this_month) - (cutoff_year * 12 + cutoff_month) ))

snapshot=""
found=0

# Cargo.toml — Rust
for cargo in $(find "$cwd" -maxdepth 3 -name "Cargo.toml" -not -path "*/target/*" -not -path "*/node_modules/*" 2>/dev/null | head -3); do
  proj=$(grep -E '^name\s*=' "$cargo" | head -1 | sed 's/.*=\s*"\([^"]*\)".*/\1/')
  edition=$(grep -E '^edition\s*=' "$cargo" | head -1 | sed 's/.*=\s*"\([^"]*\)".*/\1/')
  rust_ver=$(grep -E '^rust-version\s*=' "$cargo" | head -1 | sed 's/.*=\s*"\([^"]*\)".*/\1/')
  deps=$(grep -E '^[a-zA-Z][a-zA-Z0-9_-]*\s*=\s*[{"]' "$cargo" | head -8 | sed 's/^/    /')
  if [ -n "$proj" ]; then
    snapshot="${snapshot}  Cargo.toml ($proj) edition=${edition:-2021} rust=${rust_ver:-?}\n${deps}\n"
    found=1
  fi
done

# package.json — Node
for pkg in $(find "$cwd" -maxdepth 3 -name "package.json" -not -path "*/node_modules/*" 2>/dev/null | head -3); do
  name=$(jq -r '.name // empty' "$pkg" 2>/dev/null || true)
  node_ver=$(jq -r '.engines.node // empty' "$pkg" 2>/dev/null || true)
  deps=$(jq -r '(.dependencies // {}) | to_entries | .[0:6] | .[] | "    \(.key)=\(.value)"' "$pkg" 2>/dev/null || true)
  if [ -n "$name" ]; then
    snapshot="${snapshot}  package.json ($name) node=${node_ver:-?}\n${deps}\n"
    found=1
  fi
done

# pom.xml — Java / Maven
for pom in $(find "$cwd" -maxdepth 3 -name "pom.xml" -not -path "*/target/*" 2>/dev/null | head -3); do
  art=$(grep -m1 '<artifactId>' "$pom" | sed 's/.*<artifactId>\([^<]*\)<.*/\1/')
  java_ver=$(grep -m1 -E '<(java\.version|maven\.compiler\.source)>' "$pom" | sed 's/.*>\([^<]*\)<.*/\1/')
  parent=$(grep -A2 '<parent>' "$pom" | grep -E '<(groupId|artifactId|version)>' | sed 's/.*<\([a-z]*\)>\([^<]*\)<.*/      \1=\2/' | head -3)
  if [ -n "$art" ]; then
    snapshot="${snapshot}  pom.xml ($art) java=${java_ver:-?}\n    parent:\n${parent}\n"
    found=1
  fi
done

# requirements.txt / pyproject.toml — Python
for req in $(find "$cwd" -maxdepth 3 \( -name "requirements.txt" -o -name "pyproject.toml" \) -not -path "*/.venv/*" 2>/dev/null | head -3); do
  case "$req" in
    *requirements.txt)
      pkgs=$(head -8 "$req" | grep -vE '^\s*(#|$)' | sed 's/^/    /')
      snapshot="${snapshot}  $(basename "$(dirname "$req")")/requirements.txt:\n${pkgs}\n"
      ;;
    *pyproject.toml)
      proj_name=$(grep -m1 '^name\s*=' "$req" | sed 's/.*=\s*"\([^"]*\)".*/\1/')
      py_ver=$(grep -m1 'python\s*=' "$req" | sed 's/.*=\s*"\([^"]*\)".*/\1/')
      snapshot="${snapshot}  pyproject.toml ($proj_name) python=${py_ver:-?}\n"
      ;;
  esac
  found=1
done

# go.mod — Go
for gomod in $(find "$cwd" -maxdepth 3 -name "go.mod" 2>/dev/null | head -3); do
  module=$(head -1 "$gomod" | sed 's/^module\s*//')
  goverline=$(grep -m1 '^go\s' "$gomod" | sed 's/^go\s*//')
  snapshot="${snapshot}  go.mod ($module) go=${goverline:-?}\n"
  found=1
done

[ "$found" = "0" ] && exit 0

ctx=$(printf '[Project version snapshot — session start, %s]\nKnowledge cutoff: %s%s. Drift: ~%d months.\n\nManifest scan:\n%s\nVERSION DISCIPLINE:\n- Before proposing code that names a specific API or version, check what is true today (web search, or a docs source). Do not answer from training data.\n- Do not trust recalled idiom — "this is how axum routes work", "this is the react hooks pattern", "spring does it this way". That memory is a snapshot and the ecosystem moved.\n- The versions above are what is ACTUALLY installed here. What surrounds them is newer.\n\nRe-read the manifest itself if you need the detail.' "$today" "$cutoff" "$cutoff_note" "$months_drift" "$snapshot")

jq -n --arg ctx "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
