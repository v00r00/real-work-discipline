#!/bin/sh
# PostToolUse hook on Write | Edit. Scans a test file that was just written for
# the patterns that mean an assertion was weakened or a test was switched off.
#
# Catches:
#   } catch (              — an exception swallowed by the test itself
#   @Disabled / @Ignore    — JUnit / Kotlin skip annotations
#   assumeTrue / Assumptions — conditional skip: green because it never ran
#   pytest.skip / @pytest.mark.skip
#   TODO / FIXME in test code
#
# Warns, never blocks. Several of these patterns are legitimate (a cleanup catch
# in @AfterEach, an expected-exception assertion); the point is that each one gets
# said out loud instead of slipping past.

set -e

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *Test.java|*IT.java|*Tests.java|*Test.kt|*IT.kt|*Tests.kt|*test_*.py|*_test.py|*.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) ;;
  *) exit 0 ;;
esac

matches=$(grep -nE '\} catch \(|@Disabled|@Ignore\b|\bassumeTrue\b|\bassumeThat\b|\bAssumptions\.|pytest\.skip|@pytest\.mark\.skip|\.skip\(|\.todo\(|// *TODO|// *FIXME|# *TODO|# *FIXME' "$file" 2>/dev/null || true)

[ -z "$matches" ] && exit 0

warning=$(printf 'TEST DISCIPLINE WARNING — %s\n\nPatterns found that usually mean a weakened assertion, a skipped test, or unfinished work. Either justify each match in your next message with a real reason (cleanup-only catch in @AfterEach, expected-exception assertion via assertThatThrownBy, and so on) OR rewrite the test:\n\n%s' "$file" "$matches")

jq -n \
  --arg msg "Test discipline warning in $(basename "$file") — see model context" \
  --arg ctx "$warning" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
