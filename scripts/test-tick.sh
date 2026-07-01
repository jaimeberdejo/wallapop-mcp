#!/usr/bin/env bash
# test-tick.sh — behavioral tests for the shared completion gate (scripts/tick.sh) and the
# authoritative evidence producer (scripts/test-evidence.sh). Runs the REAL scripts in
# throwaway git repos and asserts: a phase ticks ONLY with a PASS grade + fresh green test
# evidence bound to HEAD; every missing/stale/malformed/red/secret/high-stakes case is
# fail-closed and leaves docs/ROADMAP.md byte-identical. Exit 0 = all gates behave.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TICK="$SCAFFOLD/scripts/tick.sh"
EVID="$SCAFFOLD/scripts/test-evidence.sh"
RG="$SCAFFOLD/scripts/record-grade.sh"
HS_LIB="$SCAFFOLD/.claude/lib/_high-stakes.sh"
SS_LIB="$SCAFFOLD/.claude/lib/_secret-scan.sh"
TC_LIB="$SCAFFOLD/.claude/lib/_test-cmd.sh"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

for f in "$TICK" "$EVID" "$RG" "$HS_LIB" "$SS_LIB" "$TC_LIB"; do
  [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }
done
command -v jq  >/dev/null 2>&1 || { echo "test: jq required";  exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-tick)"
cleanup() { rm -rf "$WORK" 2>/dev/null; }
trap cleanup EXIT

# mkrepo <name> [path] [content]: a repo with one open phase and a committed phase change.
# Default change is a benign src file; pass path/content to plant high-stakes or secrets.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  local path="${2:-src/widget.py}" content="${3:-def widget(): return 1}"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts" "$REPO/docs"
  cp "$TICK" "$REPO/scripts/tick.sh"
  cp "$HS_LIB" "$REPO/.claude/lib/_high-stakes.sh"
  cp "$SS_LIB" "$REPO/.claude/lib/_secret-scan.sh"
  printf '## Phase 1 — Work\n\n- [ ] do the work\n' > "$REPO/docs/ROADMAP.md"
  printf 'next: work\n' > "$REPO/docs/STATE.md"
  cat > "$REPO/.gitignore" <<'GI'
NEXT_FINDINGS.md
test-results.json
.claude/.tick-evidence.json
.claude/.phase-base
.claude/.phase-ready
.claude/.phase-grade
GI
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git config gc.auto 0 && git add -A && git commit -q -m init \
      && git rev-parse HEAD > .claude/.phase-base \
      && mkdir -p "$(dirname "$path")" && printf '%s\n' "$content" > "$path" \
      && git add -A && git commit -q -m build \
      && printf '## Phase 1 — Work\n' > .claude/.phase-ready )
  HEAD=$(git -C "$REPO" rev-parse HEAD)
}
# good evidence for the current HEAD; individual tests override pieces.
# First arg may be a short repo name (resolved under $WORK) or a full path.
_resolve()     { case "$1" in */*) printf '%s' "$1" ;; *) printf '%s/%s' "$WORK" "$1" ;; esac; }
set_grade()    { printf 'run_id=%s\nverdict=%s\nno_tests_ok=%s\n' "$2" "$3" "${4:-0}" > "$(_resolve "$1")/.claude/.phase-grade"; }
set_evidence() { printf '%s\n' "$2" > "$(_resolve "$1")/.claude/.tick-evidence.json"; }
good_grade()   { set_grade "$1" "$HEAD" PASS 0; }
good_evidence(){ set_evidence "$1" "{\"passed\":true,\"run_id\":\"$HEAD\"}"; }
runtick() { local r="$1"; shift; ( cd "$r" && bash scripts/tick.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }
ticked()  { ! grep -q '\- \[ \] do the work' "$1/docs/ROADMAP.md"; }   # 0 if ticked
md5of()   { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

echo "tick gate tests"; echo ""

# 1 — PASS grade + fresh passed:true → ticks AND updates the STATE machine block.
mkrepo t1; good_grade t1; good_evidence t1; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "PASS + fresh green evidence → ticks" || fail "did not tick on valid evidence (rc=$rc)"
{ grep -q "lean:auto:begin" "$REPO/docs/STATE.md" && grep -q "Last ticked" "$REPO/docs/STATE.md"; } \
  && pass "successful tick writes the STATE machine block" || fail "STATE machine block not written on tick"

# 2 — passed:false → refuses, roadmap unchanged, NEXT_FINDINGS written.
mkrepo t2; good_grade t2; set_evidence t2 "{\"passed\":false,\"run_id\":\"$HEAD\"}"
before=$(md5of "$REPO/docs/ROADMAP.md"); rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && [ "$before" = "$(md5of "$REPO/docs/ROADMAP.md")" ] && [ -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "passed:false → refuses, roadmap byte-identical, NEXT_FINDINGS written" || fail "passed:false mishandled (rc=$rc)"

# 3 — missing evidence file → refuses.
mkrepo t3; good_grade t3; rm -f "$REPO/.claude/.tick-evidence.json"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing test evidence → refuses" || fail "missing evidence mishandled (rc=$rc)"

# 4 — malformed evidence JSON → refuses.
mkrepo t4; good_grade t4; set_evidence t4 "{not json"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "malformed evidence → refuses" || fail "malformed evidence mishandled (rc=$rc)"

# 5 — stale evidence (run_id != HEAD) → refuses.
mkrepo t5; good_grade t5; set_evidence t5 "{\"passed\":true,\"run_id\":\"deadbeefstale\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "stale evidence (run_id mismatch) → refuses" || fail "stale evidence mishandled (rc=$rc)"

# 5b — missing .claude/.phase-base → refuses (would otherwise narrow secret/high-stakes scan).
mkrepo t5b; good_grade t5b; good_evidence t5b; rm -f "$REPO/.claude/.phase-base"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing .phase-base → refuses (no scan-window narrowing)" || fail "missing phase-base mishandled (rc=$rc)"

# 6a — passed:null + grade no_tests_ok=1 → ticks.
mkrepo t6; set_grade t6 "$HEAD" PASS 1; set_evidence t6 "{\"passed\":null,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 0 ] && ticked "$REPO"; } && pass "passed:null + NO_TESTS_OK → ticks" || fail "null+NO_TESTS_OK did not tick (rc=$rc)"
# 6b — passed:null WITHOUT no_tests_ok → refuses.
mkrepo t6b; set_grade t6b "$HEAD" PASS 0; set_evidence t6b "{\"passed\":null,\"run_id\":\"$HEAD\"}"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "passed:null without NO_TESTS_OK → refuses" || fail "null without confirm mishandled (rc=$rc)"

# 7a — missing grade → refuses.
mkrepo t7; good_evidence t7; rm -f "$REPO/.claude/.phase-grade"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "missing evaluator grade → refuses" || fail "missing grade mishandled (rc=$rc)"
# 7b — grade run_id mismatch (stale grade) → refuses.
mkrepo t7b; set_grade t7b "oldsha" PASS 0; good_evidence t7b; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "stale grade (run_id mismatch) → refuses" || fail "stale grade mishandled (rc=$rc)"
# 7c — verdict != PASS → refuses.
mkrepo t7c; set_grade t7c "$HEAD" NEEDS_WORK 0; good_evidence t7c; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "non-PASS verdict → refuses" || fail "non-PASS verdict mishandled (rc=$rc)"

# 8 — secret in the phase diff → refuses, roadmap unchanged.
mkrepo t8 src/cfg.py 'AWS="AKIAIOSFODNN7EXAMPLE"'; good_grade t8; good_evidence t8
before=$(md5of "$REPO/docs/ROADMAP.md"); rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO" && [ "$before" = "$(md5of "$REPO/docs/ROADMAP.md")" ]; } \
  && pass "secret in phase diff → refuses, roadmap byte-identical" || fail "secret-in-diff mishandled (rc=$rc)"

# 9 — high-stakes PATH change → exit 3 (supervised), not ticked, NO NEXT_FINDINGS.
mkrepo t9 auth/login.py 'def login(): return True'; good_grade t9; good_evidence t9; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO" && [ ! -f "$REPO/NEXT_FINDINGS.md" ]; } \
  && pass "high-stakes path → exit 3 supervised, not ticked" || fail "high-stakes path mishandled (rc=$rc)"

# 9b — high-stakes CONTENT in a benignly-named path → exit 3, not ticked.
mkrepo t9b src/utils.py 'cursor.execute("DROP TABLE users")'; good_grade t9b; good_evidence t9b; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "high-stakes content (DROP TABLE in benign path) → exit 3" || fail "content high-stakes mishandled (rc=$rc)"

# 9c — a phase marked "Mode: supervised" → exit 3 (enforced), not ticked.
mkrepo t9c; printf 'Mode: supervised\n' >> "$REPO/docs/ROADMAP.md"; good_grade t9c; good_evidence t9c; rc=$(runtick "$REPO")
{ [ "$rc" = 3 ] && ! ticked "$REPO"; } && pass "Mode: supervised → exit 3 (tag enforced, not auto-ticked)" || fail "Mode:supervised not enforced (rc=$rc)"

# 10 — already-ticked phase (no open item) → refuses.
mkrepo t10; good_grade t10; good_evidence t10
sed_i() { perl -i -pe 's/- \[ \] do the work/- [x] do the work/' "$1"; }
sed_i "$REPO/docs/ROADMAP.md"; rc=$(runtick "$REPO")
[ "$rc" = 1 ] && pass "no open item under heading → refuses" || fail "already-ticked mishandled (rc=$rc)"

# 11 — heading not present verbatim as a line → refuses (heading-existence gate).
mkrepo t11; good_grade t11; good_evidence t11; rc=$(runtick "$REPO" "## Phase 99 — Nope")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "bogus heading (absent) → refuses" || fail "bogus heading mishandled (rc=$rc)"
# 11b — a substring of a real heading (not a full line) → refuses (exact -x match hardening).
mkrepo t11b; good_grade t11b; good_evidence t11b; rc=$(runtick "$REPO" "Phase 1")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "heading substring (not a full line) → refuses" || fail "heading substring mishandled (rc=$rc)"

# 12 — malformed/garbage grade file (no run_id=/verdict= fields) → refuses.
mkrepo t12; good_evidence t12; printf 'garbage not a grade\n' > "$REPO/.claude/.phase-grade"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "malformed grade file → refuses" || fail "malformed grade mishandled (rc=$rc)"

# 13 — invalid .claude/.phase-base → secret scan cannot resolve the range → fail-closed refuse
#      (guards against a forged/rewritten base silently narrowing OR bypassing the secret/high-stakes scan).
mkrepo t13; good_grade t13; good_evidence t13
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "$REPO/.claude/.phase-base"; rc=$(runtick "$REPO")
{ [ "$rc" = 1 ] && ! ticked "$REPO"; } && pass "invalid .phase-base (unresolvable range) → fail-closed refuse" || fail "invalid phase-base mishandled (rc=$rc)"

echo ""
echo "test-evidence producer tests"; echo ""

mkevrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"
  mkdir -p "$REPO/.claude/lib" "$REPO/scripts"
  cp "$EVID" "$REPO/scripts/test-evidence.sh"; cp "$TC_LIB" "$REPO/.claude/lib/_test-cmd.sh"
  cp "$RG" "$REPO/scripts/record-grade.sh"
  printf '.claude/.tick-evidence.json\n' > "$REPO/.gitignore"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
  HEAD=$(git -C "$REPO" rev-parse HEAD)
}

# e1 — green suite → exit 0, passed:true, run_id == HEAD.
mkevrepo e1; ( cd "$REPO" && LEAN_TEST_CMD=true bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
ev="$REPO/.claude/.tick-evidence.json"
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$ev")" = true ] && [ "$(jq -r .run_id "$ev")" = "$HEAD" ]; } \
  && pass "test-evidence: green suite → exit0, passed:true, run_id==HEAD" || fail "green suite evidence wrong (rc=$erc)"

# e2 — red suite → exit 1, passed:false.
mkevrepo e2; ( cd "$REPO" && LEAN_TEST_CMD=false bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 1 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = false ]; } \
  && pass "test-evidence: red suite → exit1, passed:false" || fail "red suite evidence wrong (rc=$erc)"

# e3 — no test command, default → exit 1 (fail-closed), passed:null.
mkevrepo e3; ( cd "$REPO" && bash scripts/test-evidence.sh >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 1 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = null ]; } \
  && pass "test-evidence: no tests default → exit1 (fail-closed), passed:null" || fail "no-tests default wrong (rc=$erc)"

# e4 — no test command, --allow-no-tests → exit 0, passed:null.
mkevrepo e4; ( cd "$REPO" && bash scripts/test-evidence.sh --allow-no-tests >/dev/null 2>&1 ); erc=$?
{ [ "$erc" = 0 ] && [ "$(jq -r .passed "$REPO/.claude/.tick-evidence.json")" = null ]; } \
  && pass "test-evidence: no tests --allow-no-tests → exit0, passed:null" || fail "no-tests allow wrong (rc=$erc)"

echo ""
echo "record-grade producer tests"; echo ""

# g1 — PASS verdict → grade with run_id==HEAD, verdict=PASS, no_tests_ok=0.
mkevrepo g1
( cd "$REPO" && bash scripts/record-grade.sh "all criteria met
PASS" ) >/dev/null 2>&1; grc=$?
gf="$REPO/.claude/.phase-grade"
{ [ "$grc" = 0 ] && grep -q "verdict=PASS" "$gf" && grep -q "run_id=$HEAD" "$gf" && grep -q "no_tests_ok=0" "$gf"; } \
  && pass "record-grade: PASS → grade bound to HEAD, no_tests_ok=0" || fail "record-grade PASS wrong (rc=$grc)"

# g2 — verdict carrying NO_TESTS_OK → no_tests_ok=1.
mkevrepo g2
( cd "$REPO" && bash scripts/record-grade.sh "no suite for this docs phase
NO_TESTS_OK
PASS" ) >/dev/null 2>&1
grep -q "no_tests_ok=1" "$REPO/.claude/.phase-grade" 2>/dev/null \
  && pass "record-grade: NO_TESTS_OK token recorded" || fail "record-grade did not record NO_TESTS_OK"

# g3 — non-PASS verdict → refuses, writes no grade file.
mkevrepo g3
( cd "$REPO" && bash scripts/record-grade.sh "NEEDS_WORK: missing tests" ) >/dev/null 2>&1; grc=$?
{ [ "$grc" = 1 ] && [ ! -f "$REPO/.claude/.phase-grade" ]; } \
  && pass "record-grade: non-PASS refuses, no grade written" || fail "record-grade non-PASS wrong (rc=$grc)"

# g4 — a per-criterion 'PASS' that is not the final line must NOT record a grade.
mkevrepo g4
( cd "$REPO" && bash scripts/record-grade.sh "Criterion 1: PASS
NEEDS_WORK: criterion 2 unmet" ) >/dev/null 2>&1; grc=$?
{ [ "$grc" = 1 ] && [ ! -f "$REPO/.claude/.phase-grade" ]; } \
  && pass "record-grade: mid-text 'PASS' line does not record (anchored last line)" || fail "record-grade anchored-parse wrong (rc=$grc)"

# g5 — NO_TESTS_OK appearing only mid-sentence (e.g. echoed from a diff) must NOT set the flag,
# so a passed:null phase can't skip the test gate via an incidental token in the verdict text.
mkevrepo g5
( cd "$REPO" && bash scripts/record-grade.sh "the diff adds a NO_TESTS_OK constant to a comment
PASS" ) >/dev/null 2>&1
grep -q "no_tests_ok=0" "$REPO/.claude/.phase-grade" 2>/dev/null \
  && pass "record-grade: mid-sentence NO_TESTS_OK ignored (leading-token only)" || fail "record-grade substring bypass NOT closed"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All tick gate + evidence tests passed."; exit 0
else echo "$FAILS tick test(s) FAILED."; echo "--- last tick output ---"; tail -n 20 "$WORK/out" 2>/dev/null; exit 1; fi
