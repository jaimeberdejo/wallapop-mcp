#!/usr/bin/env bash
# test-autopilot-gates.sh — behavioral regression tests for autopilot.sh's safety gates.
# Runs the REAL scripts/autopilot.sh in throwaway repos with a STUBBED `claude`/`gh` on PATH,
# so we assert actual control-flow — not source strings. The stub `claude` distinguishes the
# evaluator (`--agent`) from the builder and is driven by BUILDER_MODE / EVAL_MODE.
#
# Guarantees covered: high-stakes never pushed (--pr); evaluator edits discarded; evaluator
# COMMIT reverts + stops; empty/garbled verdict never ticks; NEEDS_WORK doesn't tick; clean
# PASS ticks; a secret in the builder's commits blocks the --pr push.
# Exit 0 = all gates behave correctly.

set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOPILOT="$SCAFFOLD/scripts/autopilot.sh"
TICK="$SCAFFOLD/scripts/tick.sh"
EVID="$SCAFFOLD/scripts/test-evidence.sh"
RG="$SCAFFOLD/scripts/record-grade.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"
TC_LIB="$SCAFFOLD/.claude/lib/_test-cmd.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

[ -f "$AUTOPILOT" ] || { echo "test: cannot find autopilot.sh at $AUTOPILOT" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "test: jq required";  exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack)"
cleanup() { rm -rf "$WORK" 2>/dev/null; git worktree prune 2>/dev/null; }
trap cleanup EXIT

# --- stubs: env-driven fake `claude` (builder + evaluator) and a loud fake `gh` ---
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'STUB'
#!/usr/bin/env bash
# Evaluator invocation carries --agent.
is_eval=0; for a in "$@"; do [ "$a" = "--agent" ] && is_eval=1; done
if [ "$is_eval" = 1 ]; then
  case "${EVAL_MODE:-pass}" in
    pass)        echo "PASS" ;;
    pass_edit)   echo "tampered_by_evaluator" >> src/widget.py 2>/dev/null; echo "PASS" ;;
    pass_commit) echo "x" > eval_sneak.txt; git add -A >/dev/null 2>&1; git commit -qm "evaluator sneak commit" >/dev/null 2>&1; echo "PASS" ;;
    empty)       printf '' ;;
    garble)      echo "looks good to me, ship it" ;;
    needs_work)  echo "NEEDS_WORK: missing tests" ;;
    needs_then_pass)
      # NEEDS_WORK on the first grade, PASS thereafter — counter lives OUTSIDE the repo so
      # cleanup_eval_changes (which discards files the grader creates) can't reset it.
      cf="${EVAL_COUNT_FILE:-/tmp/lean_eval_count}"
      n=$(cat "$cf" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$cf"
      if [ "$n" -ge 2 ]; then echo "PASS"; else echo "NEEDS_WORK: needs a second pass"; fi
      ;;
  esac
  exit 0
fi
# Builder: record refs like /phase does, then write+commit per BUILDER_MODE.
git rev-parse HEAD > .claude/.phase-base 2>/dev/null
printf '## Phase 1 — Work\n' > .claude/.phase-ready
case "${BUILDER_MODE:-highstakes}" in
  highstakes) mkdir -p auth; echo "def login(): return True" > auth/login.py ;;
  clean)      mkdir -p src;  echo "def widget(): return 1"   > src/widget.py ;;
  secret)     mkdir -p src;  printf 'AWS="AKIAIOSFODNN7EXAMPLE"\n' > src/cfg.py ;;
esac
git add -A 2>/dev/null; git commit -qm "build" 2>/dev/null
exit 0
STUB
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
echo "STUB-GH-INVOKED: $*"
exit 0
STUB
chmod +x "$BIN/claude" "$BIN/gh"

# mkrepo <name>: a fake installed lean-stack tree with one open phase.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$AUTOPILOT" "$REPO/scripts/autopilot.sh"
  cp "$TICK" "$REPO/scripts/tick.sh"
  cp "$EVID" "$REPO/scripts/test-evidence.sh"
  cp "$RG" "$REPO/scripts/record-grade.sh"
  cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"
  cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"
  cp "$TC_LIB" "$REPO/.claude/lib/_test-cmd.sh"
  printf '{ "permissions": { "deny": ["Read(.env)"] } }\n' > "$REPO/.claude/settings.json"
  # Mirror a real install's .gitignore so log/evidence/control files stay UNTRACKED — exactly
  # like a shipped project. Without this the stub would commit autopilot.log and the .claude
  # control files, and appending to them (e.g. test-evidence's log) would dirty the tracked
  # tree and trip the evaluator-change cleanup. (Faithfulness, not a workaround.)
  cat > "$REPO/.gitignore" <<'GI'
autopilot.log
*.log
NEXT_FINDINGS.md
AGENT_STOP
STEER.md
test-results.json
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
.claude/.autopilot.lock
.claude/.last-changed
GI
  printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
  printf 'next: work\n' > "$REPO/docs/STATE.md"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config gc.auto 0 && git add -A && git commit -q -m init )
}
# run <repo> <flags...>: run autopilot with the stubs; output captured OUTSIDE the repo.
# LEAN_TEST_CMD=true gives test-evidence.sh a green suite (stub repos have no real tests),
# so the tick gate's fresh-green-evidence requirement is satisfied for the control-flow tests.
# The evidence gate's own refuse paths (red/stale/missing/null) are covered in test-tick.sh.
run() { local r="$1"; shift; ( cd "$r" && PATH="$BIN:$PATH" LEAN_TEST_CMD=true bash scripts/autopilot.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }
ticked()   { ! grep -q '\- \[ \] do the work' "$1/docs/ROADMAP.md"; }   # 0 if ticked
# Pipe-free substring test. NEVER use `cmd | grep -q` under `set -o pipefail`: grep -q
# closes the pipe on first match, cmd dies with SIGPIPE, and pipefail reports failure
# even though the match succeeded — a real intermittent flake.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
logof()    { git -C "$1" log --oneline 2>/dev/null; }

echo "autopilot gate tests"; echo ""

# 1 — P0: high-stakes phase + --pr must NOT push / open a PR, and must not tick.
mkrepo r1; BUILDER_MODE=highstakes EVAL_MODE=pass; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --pr >/dev/null
grep -q "HIGH-STAKES paths changed" "$WORK/out" && pass "high-stakes gate fires" || fail "high-stakes gate did not fire"
grep -q "stays LOCAL" "$WORK/out" && pass "high-stakes branch stays local" || fail "no 'stays LOCAL'"
grep -qE "pushing .* and opening a PR|STUB-GH-INVOKED" "$WORK/out" && fail "PUSH/PR ENTERED on high-stakes (P0 REGRESSION)" || pass "no push / no PR on high-stakes (P0)"
ticked "$REPO" && fail "high-stakes roadmap was ticked" || pass "high-stakes roadmap left unticked"

# 2 — evaluator that COMMITS during grading must be reverted + STOP (not ticked).
mkrepo r2; BUILDER_MODE=clean EVAL_MODE=pass_commit; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
grep -q "evaluator COMMITTED during grading" "$WORK/out" && pass "evaluator commit detected" || fail "evaluator commit NOT detected"
ticked "$REPO" && fail "ticked despite evaluator commit" || pass "not ticked after evaluator commit"
contains "$(logof "$REPO")" "evaluator sneak commit" && fail "evaluator commit survived in HEAD" || pass "evaluator commit reverted from HEAD"

# 3 — evaluator that EDITS the tree but says PASS: edits discarded, phase ticks from clean tree.
mkrepo r3; BUILDER_MODE=clean EVAL_MODE=pass_edit; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
ticked "$REPO" && pass "clean PASS ticks after discarding evaluator edit" || fail "did not tick on clean PASS"
contains "$(git -C "$REPO" show HEAD:src/widget.py 2>/dev/null)" tampered_by_evaluator && fail "evaluator edit leaked into commit" || pass "evaluator edit discarded (not in commit)"

# 4 — empty verdict → stop, never tick.
mkrepo r4; BUILDER_MODE=clean EVAL_MODE=empty; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
grep -q "no output" "$WORK/out" && ! ticked "$REPO" && pass "empty verdict stops, not ticked" || fail "empty verdict mishandled"

# 5 — garbled final line → unrecognized verdict, stop, never tick.
mkrepo r5; BUILDER_MODE=clean EVAL_MODE=garble; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
grep -q "unrecognized verdict" "$WORK/out" && ! ticked "$REPO" && pass "garbled verdict stops, not ticked" || fail "garbled verdict mishandled"

# 6 — clean PASS (no tampering) → routes through scripts/tick.sh, ticks and commits the phase.
mkrepo r6; BUILDER_MODE=clean EVAL_MODE=pass; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
grep -q "tick: .* ticked" "$WORK/out" && pass "clean PASS routes through scripts/tick.sh" || fail "tick.sh not invoked on clean PASS"
ticked "$REPO" && pass "clean PASS ticks the roadmap" || fail "clean PASS did not tick"
contains "$(logof "$REPO")" "passed independent grade" && pass "clean PASS commits the phase" || fail "clean PASS did not commit"

# 7 — a secret in the builder's commits + --pr → push gate blocks, exit 1, no gh.
mkrepo r7; BUILDER_MODE=secret EVAL_MODE=pass; export BUILDER_MODE EVAL_MODE; rc=$(run "$REPO" 1 --pr)
grep -qE "commit range contains a secret|NOT pushing" "$WORK/out" && pass "push gate catches secret in range" || fail "push gate missed secret"
grep -q "STUB-GH-INVOKED" "$WORK/out" && fail "gh invoked despite secret" || pass "no gh / no push on secret range"
[ "$rc" = 1 ] && pass "secret push-gate exits non-zero" || fail "secret push-gate exit was $rc (want 1)"

# 8 — NEEDS_WORK never ticks, writes NEXT_FINDINGS.md, and repeated NEEDS_WORK hits the thrash cap.
mkrepo r8; BUILDER_MODE=clean EVAL_MODE=needs_work; export BUILDER_MODE EVAL_MODE; run "$REPO" 3 --no-worktree --allow-dirty >/dev/null
ticked "$REPO" && fail "NEEDS_WORK ticked the roadmap" || pass "NEEDS_WORK never ticks"
[ -f "$REPO/NEXT_FINDINGS.md" ] && pass "NEEDS_WORK writes NEXT_FINDINGS.md" || fail "NEXT_FINDINGS.md not written"
grep -q "same phase failed" "$WORK/out" && pass "repeated NEEDS_WORK hits the thrash cap and stops" || fail "thrash cap did not trigger"

# 9 — NEEDS_WORK then PASS: the resolved finding is ARCHIVED to docs/FAILURES.md (not just
#     deleted), the phase ticks, and NEXT_FINDINGS.md is cleared.
mkrepo r9; rm -f "$WORK/ec9"
BUILDER_MODE=clean EVAL_MODE=needs_then_pass EVAL_COUNT_FILE="$WORK/ec9"
export BUILDER_MODE EVAL_MODE EVAL_COUNT_FILE
run "$REPO" 2 --no-worktree --allow-dirty >/dev/null
unset EVAL_COUNT_FILE
ticked "$REPO" && pass "needs_then_pass eventually ticks" || fail "needs_then_pass never ticked"
{ [ -f "$REPO/docs/FAILURES.md" ] && grep -q "second pass" "$REPO/docs/FAILURES.md"; } \
  && pass "resolved finding archived to docs/FAILURES.md" || fail "failure not archived to FAILURES.md"
[ ! -f "$REPO/NEXT_FINDINGS.md" ] && pass "NEXT_FINDINGS.md cleared after archive" || fail "NEXT_FINDINGS.md not cleared"

# 10 — concurrency lock: a live lock (this test's own pid) makes a second run refuse.
mkrepo r10; mkdir -p "$REPO/.claude"; echo "$$" > "$REPO/.claude/.autopilot.lock"
BUILDER_MODE=clean EVAL_MODE=pass; export BUILDER_MODE EVAL_MODE; rc=$(run "$REPO" 1 --no-worktree --allow-dirty)
{ [ "$rc" = 1 ] && grep -q "another autopilot run is active" "$WORK/out" && ! ticked "$REPO"; } \
  && pass "live lock → second run refuses (no concurrent run)" || fail "concurrency lock did not hold (rc=$rc)"

# 11 — stale lock from a dead pid is reclaimed, and the run proceeds + releases the lock.
mkrepo r11; mkdir -p "$REPO/.claude"; echo "999999" > "$REPO/.claude/.autopilot.lock"
BUILDER_MODE=clean EVAL_MODE=pass; export BUILDER_MODE EVAL_MODE; run "$REPO" 1 --no-worktree --allow-dirty >/dev/null
grep -q "stale lock" "$WORK/out" && pass "stale lock (dead pid) is reclaimed" || fail "stale lock not reclaimed"
ticked "$REPO" && pass "run proceeds after reclaiming a stale lock" || fail "did not proceed after stale lock"
[ ! -f "$REPO/.claude/.autopilot.lock" ] && pass "lock released on normal exit (trap)" || fail "lock not released after run"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All autopilot gate tests passed."; exit 0
else echo "$FAILS gate test(s) FAILED."; echo "--- last run output ---"; tail -n 25 "$WORK/out" 2>/dev/null; exit 1; fi
