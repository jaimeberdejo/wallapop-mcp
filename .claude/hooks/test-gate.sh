#!/usr/bin/env bash
# Stop hook — deterministic GREEN-SUITE gate (enforces "tests pass before the turn ends",
# NOT test-first ordering — that stays advisory in CLAUDE.md). Was "TDD" but that overclaimed.
# Runs the project's test suite, writes evidence to test-results.json
# (which the evaluator reads), and — in block mode — refuses to let the turn end
# while tests are red.
#
# OPT-IN via env var LEAN_TEST_GATE:
#   unset / off  → no-op (default; never surprises you, never slows turns)
#   warn         → run tests, write test-results.json, print a warning if red
#   block        → run tests, write evidence, and exit 2 (forces a fix) if red
#
# Test command resolution (first match wins):
#   1. $LEAN_TEST_CMD if set
#   2. pytest -q          (if pytest available AND a tests/ dir or test_*.py exists)
#   3. npm test --silent  (if package.json has a "test" script)
#
# Wire it FIRST in the Stop array so it gates before the checkpoint commit.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

MODE="${LEAN_TEST_GATE:-off}"
[ "$MODE" = "off" ] && exit 0

# Read the hook JSON once; don't block on a TTY / missing pipe.
if [ -t 0 ]; then INPUT='{}'; else INPUT=$(cat 2>/dev/null || echo '{}'); fi
# Avoid re-triggering ourselves if a previous block forced continuation.
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$ACTIVE" = "true" ] && exit 0

# --- resolve the test command (shared with scripts/test-evidence.sh via _test-cmd.sh) ---
CMD=""
[ -f .claude/lib/_test-cmd.sh ] && . .claude/lib/_test-cmd.sh 2>/dev/null || true
if command -v resolve_test_cmd >/dev/null 2>&1; then
  CMD=$(resolve_test_cmd 2>/dev/null || true)
fi

if [ -z "$CMD" ]; then
  # Nothing to run — record that, don't block.
  printf '{"passed":null,"command":null,"note":"no test command resolved"}\n' > test-results.json 2>/dev/null || true
  exit 0
fi

# --- run it ---
OUT=$(eval "$CMD" 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then
  printf '{"passed":true,"command":"%s","exit":0}\n' "$CMD" > test-results.json 2>/dev/null || true
  exit 0
fi

# Red.
printf '{"passed":false,"command":"%s","exit":%d}\n' "$CMD" "$RC" > test-results.json 2>/dev/null || true
TAIL=$(printf '%s\n' "$OUT" | tail -15)

if [ "$MODE" = "block" ]; then
  # Exit 2 on Stop blocks the turn from ending and feeds stderr back to Claude.
  {
    echo "TEST GATE (block mode): tests are RED — fix them before ending the turn."
    echo "command: $CMD (exit $RC)"
    echo "---"
    echo "$TAIL"
  } >&2
  exit 2
fi

# warn mode: surface it, don't block.
echo "⚠ test-gate (warn): '$CMD' failed (exit $RC). See test-results.json. Last lines:"
printf '%s\n' "$TAIL"
exit 0
