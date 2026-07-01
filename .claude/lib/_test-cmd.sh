#!/usr/bin/env bash
# _test-cmd.sh — SHARED test-command resolver (sourced, not a hook).
# Single source of truth for "how do we run THIS project's tests", used by both the
# advisory Stop hook (.claude/hooks/test-gate.sh) and the authoritative tick-evidence
# producer (scripts/test-evidence.sh) so the resolution can never drift between them.
#
# resolve_test_cmd: echoes the test command to stdout; returns 0 if one was resolved,
# 1 if none. Order (first match wins):
#   1. $LEAN_TEST_CMD if set
#   2. pytest -q          (pytest on PATH AND a tests/ dir or test_*.py exists)
#   3. npm test --silent  (package.json has a "test" script; needs jq)
resolve_test_cmd() {
  if [ -n "${LEAN_TEST_CMD:-}" ]; then
    printf '%s' "$LEAN_TEST_CMD"; return 0
  fi
  if command -v pytest >/dev/null 2>&1 && { [ -d tests ] || ls test_*.py >/dev/null 2>&1; }; then
    printf '%s' "pytest -q"; return 0
  fi
  if [ -f package.json ] && command -v jq >/dev/null 2>&1 \
     && jq -e '.scripts.test' package.json >/dev/null 2>&1; then
    printf '%s' "npm test --silent"; return 0
  fi
  return 1
}

# Sourcing only defines the function; running this file directly is a harmless no-op.
return 0 2>/dev/null || exit 0
