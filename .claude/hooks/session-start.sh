#!/usr/bin/env bash
# SessionStart hook — re-injects project state into Claude's context.
# stdout from SessionStart IS added to the context window (one of only
# a few events for which that is true), so this is the "never forget" mechanism.
# Fires on: startup, resume, clear, compact.
#
# NOTE: deliberately NOT using `set -e`. A SIGPIPE from `head` closing a pipe
# early (see the ARCHITECTURE sed|head below) would otherwise abort the hook
# and silently drop everything after it. We want best-effort, print-what-we-can.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 0

echo "=== PROJECT STATE (auto-injected) ==="

# Previous evaluator findings take priority — address these before new work.
if [ -f NEXT_FINDINGS.md ]; then
  echo "--- Previous evaluator findings (NEXT_FINDINGS.md; showing last 60 lines) ---"
  tail -60 NEXT_FINDINGS.md
  total_lines=$(wc -l < NEXT_FINDINGS.md 2>/dev/null || echo 0)
  if [ "${total_lines:-0}" -gt 60 ] 2>/dev/null; then
    echo "(truncated — read NEXT_FINDINGS.md for the full findings)"
  fi
  echo ""
fi

if [ -f docs/STATE.md ]; then
  echo "--- docs/STATE.md ---"
  # Cap it: STATE is meant to be short (current state + next action), but nothing forces that, and
  # this is injected into context every session. Bound the one previously-uncapped read.
  head -60 docs/STATE.md
  s_lines=$(wc -l < docs/STATE.md 2>/dev/null || echo 0)
  if [ "${s_lines:-0}" -gt 60 ] 2>/dev/null; then
    echo "(truncated — STATE.md is $s_lines lines; keep it short: current state + the single next action)"
  fi
fi

if [ -f docs/ARCHITECTURE.md ]; then
  echo ""
  echo "--- docs/ARCHITECTURE.md (overview only) ---"
  # Print just the overview + entry points, not the whole map, to stay lean.
  # `cat | sed | head` keeps SIGPIPE contained to a subshell so it can't abort us.
  { sed -n '1,/^## Module map/p' docs/ARCHITECTURE.md | head -40; } 2>/dev/null || true
  echo "(run the mapme skill to regenerate the full map)"
fi

if [ -f docs/ROADMAP.md ]; then
  echo ""
  echo "--- Open roadmap items ---"
  # Capture first (head closing the pipe would SIGPIPE grep and, with a trailing `|| echo`,
  # spuriously print "(none)" right after listing items). Decide from the captured text.
  OPEN_ITEMS=$(grep -n "^[[:space:]]*- \[ \] " docs/ROADMAP.md 2>/dev/null | head -20)
  if [ -n "$OPEN_ITEMS" ]; then printf '%s\n' "$OPEN_ITEMS"; else echo "(none — roadmap complete or empty)"; fi
fi

echo ""
echo "--- Recent commits ---"
git log --oneline -8 2>/dev/null || echo "(no git history yet)"

echo ""
echo "=== Read docs/SPEC.md if you need the full intent. One feature per session. ==="
