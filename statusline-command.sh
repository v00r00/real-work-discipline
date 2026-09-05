#!/bin/bash
# Status line: working directory | model | remaining context window.
#
# The context percentage is the one that matters: it is the warning that a
# compaction is coming, which is when the execution log on disk stops being
# bookkeeping and starts being the only record of what was done.
#
# Note the `printf '%b'` form. The obvious `printf "$string"` treats the string as
# a format, so the percent sign in "ctx: 72%" swallows the colour reset and every
# line after it stays yellow. Found by running the script instead of reading it.
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

YELLOW='\033[0;33m'
RESET='\033[0m'

parts="${cwd}"
[ -n "$model" ] && parts="${parts} | ${model}"
[ -n "$remaining" ] && parts="${parts} | ctx: ${remaining}%"

printf '%b' "${YELLOW}${parts}${RESET}"
