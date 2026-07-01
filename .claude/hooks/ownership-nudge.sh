#!/usr/bin/env bash
# Stop hook — ownership nudge.
# Reminds you to capture decisions and check understanding before moving on.
# Non-blocking: prints to your terminal, does not force anything.
#
# IMPORTANT ordering note: commit-on-stop.sh runs before this hook on the same
# Stop event and commits the working tree, so `git diff HEAD` is empty by the
# time we get here. We therefore read .claude/.last-changed (written by
# commit-on-stop BEFORE it committed) and fall back to the live diff.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

# Read the hook JSON once; don't block on a TTY / missing pipe.
if [ -t 0 ]; then INPUT='{}'; else INPUT=$(cat 2>/dev/null || echo '{}'); fi
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$ACTIVE" = "true" ] && exit 0

# Gather the files that changed this turn, from any of three sources.
CHANGED=""
if [ -f .claude/.last-changed ]; then
  CHANGED=$(cat .claude/.last-changed 2>/dev/null)
fi
# Fall back to live working-tree changes (manual sessions, or if checkpoint skipped).
if [ -z "$CHANGED" ]; then
  CHANGED=$( { git diff --name-only HEAD 2>/dev/null; git status --porcelain 2>/dev/null | cut -c4-; } | sort -u)
fi
# Last resort: files in the most recent commit (the checkpoint we just made).
if [ -z "$CHANGED" ]; then
  CHANGED=$(git show --name-only --pretty=format: HEAD 2>/dev/null)
fi

if grep -qE '\.(py|ts|tsx|js|jsx|go|rs)$' <<<"$CHANGED"; then
  echo "↳ ownership check:"
  echo "  • Decision made? run the adr skill to record it (with the alternative you rejected)."
  echo "  • Understand what was built? run teach-back before /wrap."
  echo "  • Big change? run the mapme skill to refresh docs/ARCHITECTURE.md."
fi

# Clean up the breadcrumb so a later no-op Stop doesn't re-nudge stale changes.
rm -f .claude/.last-changed 2>/dev/null || true
exit 0
