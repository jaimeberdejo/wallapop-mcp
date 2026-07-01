#!/usr/bin/env bash
# test-evidence.sh — AUTHORITATIVE producer of tick evidence (.claude/.tick-evidence.json).
#
# Why a dedicated producer (not the test-gate.sh Stop hook): the Stop hook runs BEFORE
# commit-on-stop.sh, and the builder updates docs/STATE.md after its last task commit, so
# commit-on-stop checkpoint-commits and ADVANCES HEAD past anything a Stop-time gate stamped.
# Bind evidence to HEAD only AFTER the builder has fully exited — that is this script's job.
# The orchestrator (scripts/autopilot.sh) and the in-session /wrap tick path call it once the
# tree is settled, so run_id == the exact commit scripts/tick.sh will verify against.
#
# It writes a SEPARATE file from the advisory test-gate.sh (which owns test-results.json), so
# the evaluator's own Stop-hook run of test-gate can't clobber the authoritative record.
#
# Output .claude/.tick-evidence.json: {passed, command, exit, run_id, note}
#   passed: true (suite green) | false (suite red) | null (no test command resolved)
# Exit: 0 = tests passed, OR no-tests with --allow-no-tests.
#       1 = tests failed, OR no test command resolved without --allow-no-tests (fail-closed:
#           "no evidence" is NOT "success"; whether null is acceptable for a TICK is decided
#           downstream by scripts/tick.sh via the evaluator's NO_TESTS_OK confirmation).
#
# Usage: bash scripts/test-evidence.sh [--allow-no-tests]
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

ALLOW_NO_TESTS=0
for a in "$@"; do
  case "$a" in
    --allow-no-tests) ALLOW_NO_TESTS=1 ;;
    *) echo "test-evidence: unknown argument '$a'" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "test-evidence: jq required" >&2; exit 1; }

OUT_FILE=".claude/.tick-evidence.json"
mkdir -p .claude 2>/dev/null || true
HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

[ -f .claude/lib/_test-cmd.sh ] && . .claude/lib/_test-cmd.sh 2>/dev/null || true
CMD=""
if command -v resolve_test_cmd >/dev/null 2>&1; then CMD=$(resolve_test_cmd 2>/dev/null || true); fi

# emit <passed-json-literal> <command-or-empty> <exit-or-null> <note-or-empty>
emit() {
  jq -nc \
     --argjson passed "$1" \
     --arg cmd "$2" \
     --argjson exit "${3:-null}" \
     --arg run_id "$HEAD" \
     --arg note "$4" \
     '{passed: $passed,
       command: (if $cmd == "" then null else $cmd end),
       exit: $exit,
       run_id: $run_id}
      + (if $note == "" then {} else {note: $note} end)' \
     > "$OUT_FILE" 2>/dev/null || true
}

if [ -z "$CMD" ]; then
  emit null "" null "no test command resolved"
  if [ "$ALLOW_NO_TESTS" -eq 1 ]; then
    echo "test-evidence: no test command resolved — recorded passed:null (--allow-no-tests)."
    exit 0
  fi
  echo "test-evidence: no test command resolved — fail-closed (pass --allow-no-tests to record null and continue)." >&2
  exit 1
fi

OUT=$(eval "$CMD" 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then
  emit true "$CMD" 0 ""
  echo "test-evidence: ✓ '$CMD' passed (run_id ${HEAD:0:12})."
  exit 0
fi

emit false "$CMD" "$RC" ""
echo "test-evidence: ✗ '$CMD' failed (exit $RC). Last lines:" >&2
printf '%s\n' "$OUT" | tail -15 >&2
exit 1
