#!/usr/bin/env bash
# record-grade.sh — write .claude/.phase-grade from an evaluator verdict so scripts/tick.sh can
# verify a phase was independently graded PASS. Used by the in-session /wrap and /autopilot tick
# paths; scripts/autopilot.sh (headless) calls it too, so the grade-file format has ONE writer.
#
# Stamps run_id = HEAD to bind the grade to the exact commit tick.sh will check. Refuses (writes
# nothing, exit 1) unless the verdict's LAST non-empty line is exactly PASS — a NEEDS_WORK or
# garbled verdict can never become a tick. If the verdict text contains NO_TESTS_OK, records it
# so tick.sh may accept a phase that legitimately has no test suite.
#
# Usage: bash scripts/record-grade.sh "<full evaluator verdict text>"
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

VERDICT="${1:-}"
[ -n "$VERDICT" ] || { echo "record-grade: pass the evaluator's verdict text as argument 1." >&2; exit 1; }

# Anchored: trust ONLY the last non-empty line, exactly like scripts/autopilot.sh.
LAST=$(printf '%s\n' "$VERDICT" | grep -vE '^[[:space:]]*$' | tail -1)
if [ "$LAST" != "PASS" ]; then
  echo "record-grade: evaluator verdict is not PASS (last line: '$LAST') — no grade recorded." >&2
  exit 1
fi

NO_TESTS_OK=0
# Match NO_TESTS_OK only as a leading token on its OWN line (per evaluator.md's contract), not as a
# bare substring — the verdict text is diff-influenced, so an incidental `NO_TESTS_OK` echoed from
# code the evaluator quoted must NOT flip the flag and let a passed:null phase skip the test gate.
printf '%s\n' "$VERDICT" | grep -qE '^[[:space:]]*NO_TESTS_OK([[:space:]]|$)' && NO_TESTS_OK=1

mkdir -p .claude
{
  echo "run_id=$(git rev-parse HEAD 2>/dev/null)"
  echo "verdict=PASS"
  echo "no_tests_ok=$NO_TESTS_OK"
} > .claude/.phase-grade
echo "record-grade: recorded PASS (no_tests_ok=$NO_TESTS_OK) at $(git rev-parse --short HEAD 2>/dev/null)."
