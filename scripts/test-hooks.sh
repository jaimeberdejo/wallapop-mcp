#!/usr/bin/env bash
# test-hooks.sh — feed each hook the kind of JSON Claude Code sends on stdin
# and confirm it runs without error. This is a smoke test, not a behavior spec:
# it catches the "hook crashes / aborts early" class of bug (the kind that
# silently broke ownership-nudge and session-start before).
#
# Run from the repo root: bash scripts/test-hooks.sh

set -uo pipefail
# Resolve the scaffold SCRIPT-RELATIVE — scripts/.. is always the scaffold root, whether that's the
# git root (installed project) or lean-stack/ (this toolkit repo). git-toplevel is NOT reliable here:
# in the toolkit repo it points at the OUTER root, and a stray .claude/ there (session artifacts, a
# parent project) would defeat a "does .claude exist?" heuristic. Script-relative is immune to both.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
export CLAUDE_PROJECT_DIR="$PWD"

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
run() {
  local name="$1" script="$2" json="$3"
  if printf '%s' "$json" | bash "$script" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$name"
  else
    printf '  ✗ %s (exit %d)\n' "$name" "$?"
    FAILS=$((FAILS+1))
  fi
}

echo "hook smoke tests"
echo ""

run "SessionStart"            .claude/hooks/session-start.sh   '{"hook_event_name":"SessionStart","source":"startup"}'
run "UserPromptSubmit/steer"  .claude/hooks/steer.sh           '{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
run "PreToolUse/steer"        .claude/hooks/steer.sh           '{"hook_event_name":"PreToolUse","tool_name":"Edit"}'
run "PreToolUse/kill-switch"  .claude/hooks/kill-switch.sh     '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
run "PostToolUse/format"      .claude/hooks/format-on-edit.sh  '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"/nonexistent.py"}}'
run "Stop/test-gate(off)"     .claude/hooks/test-gate.sh       '{"hook_event_name":"Stop","stop_hook_active":false}'
run "Stop/commit"             .claude/hooks/commit-on-stop.sh  '{"hook_event_name":"Stop","stop_hook_active":true}'
run "Stop/ownership"          .claude/hooks/ownership-nudge.sh '{"hook_event_name":"Stop","stop_hook_active":true}'

echo ""
# Verify kill-switch actually blocks (exit 2) when AGENT_STOP exists.
touch AGENT_STOP
if printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1; then
  printf '  ✗ kill-switch did NOT block with AGENT_STOP present\n'; FAILS=$((FAILS+1))
else
  printf '  ✓ kill-switch blocks (exit 2) when AGENT_STOP present\n'
fi
rm -f AGENT_STOP

# Verify kill-switch FAILS CLOSED even when CLAUDE_PROJECT_DIR is unset.
# Under `set -u`, an unset var must NOT abort the hook before the AGENT_STOP check.
(
  unset CLAUDE_PROJECT_DIR
  touch AGENT_STOP
  printf '%s' '{"hook_event_name":"PreToolUse"}' | bash .claude/hooks/kill-switch.sh >/dev/null 2>&1
  rc=$?
  rm -f AGENT_STOP
  exit "$rc"
)
if [ "$?" -eq 2 ]; then
  printf '  ✓ kill-switch fails closed (exit 2) when CLAUDE_PROJECT_DIR unset\n'
else
  printf '  ✗ kill-switch did NOT fail closed with CLAUDE_PROJECT_DIR unset\n'; FAILS=$((FAILS+1))
fi

# Harder case: env var unset AND invoked from a SUBDIRECTORY. The brake must still fire
# (resolve the repo root via `git rev-parse --show-toplevel`), not fail open.
(
  unset CLAUDE_PROJECT_DIR
  t=$(mktemp -d) || exit 20
  trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/subdir" || exit 21
  cp .claude/hooks/kill-switch.sh "$t/.claude/hooks/" || exit 22
  cd "$t" || exit 23
  git init -q || exit 24
  touch AGENT_STOP
  cd subdir || exit 25
  printf '%s' '{"hook_event_name":"PreToolUse"}' | bash "$t/.claude/hooks/kill-switch.sh" >/dev/null 2>&1
  rc=$?
  exit "$rc"
)
ks_sub_rc=$?
if [ "$ks_sub_rc" -eq 2 ]; then
  printf '  ✓ kill-switch fails closed from a subdir with CLAUDE_PROJECT_DIR unset\n'
else
  printf '  ✗ kill-switch FAILED OPEN from a subdir (rc=%s)\n' "$ks_sub_rc"; FAILS=$((FAILS+1))
fi

# Wiring assertion: the brake is only effective if settings.json actually dispatches
# kill-switch.sh on EVERY tool call. Per the Claude Code hooks docs, "*", "" and an
# omitted matcher all mean match-all; a narrowed matcher (e.g. "Bash") would fail open.
# (Unit-asserts the wiring shape; live harness dispatch can only be confirmed at runtime.)
if jq -e '
      [ .hooks.PreToolUse[]?
        | select([.hooks[]?.command | select(test("kill-switch"))] | length > 0)
        | (.matcher // "*") ] as $ms
      | ($ms | length > 0) and ($ms | all(. == "" or . == "*"))
    ' .claude/settings.json >/dev/null 2>&1; then
  printf '  ✓ kill-switch wired into PreToolUse with a match-all matcher\n'
else
  printf '  ✗ kill-switch NOT wired match-all in PreToolUse (brake may not fire on every tool)\n'; FAILS=$((FAILS+1))
fi

echo ""
# Verify the SHARED secret-scan library blocks a planted credential and does NOT
# false-positive on a clean file. Runs in an ISOLATED temp git repo so we never
# stage a secret into this repo.
SCAN_LIB="$PWD/.claude/lib/_secret-scan.sh"
if [ -f "$SCAN_LIB" ]; then
  (
    set -uo pipefail
    tmp=$(mktemp -d) || exit 20
    trap 'rm -rf "$tmp"' EXIT
    cd "$tmp" || exit 21
    git init -q . && git config user.email t@t.t && git config user.name t || exit 22
    . "$SCAN_LIB"
    # 1) a high-confidence token in an ordinary file MUST be flagged (rc 1).
    printf 'aws_key = "AKIA1234567890ABCDEF"\n' > config.py
    git add config.py
    secret_scan_staged >/dev/null 2>&1; src=$?
    [ "$src" -eq 1 ] || exit 11
    # 2) a clean staged file MUST pass (rc 0).
    git reset -q
    printf 'x = 1\n' > ok.py
    git add ok.py
    secret_scan_staged >/dev/null 2>&1; src=$?
    [ "$src" -eq 0 ] || exit 12
    exit 0
  )
  rc=$?
  case "$rc" in
    0)  printf '  ✓ secret-scan blocks a planted AWS key and passes a clean file\n' ;;
    11) printf '  ✗ secret-scan did NOT flag a planted AWS key\n'; FAILS=$((FAILS+1)) ;;
    12) printf '  ✗ secret-scan false-positived on a clean file\n'; FAILS=$((FAILS+1)) ;;
    *)  printf '  ✗ secret-scan test harness errored (rc=%d)\n' "$rc"; FAILS=$((FAILS+1)) ;;
  esac
else
  printf '  ✗ missing .claude/lib/_secret-scan.sh (shared secret-scan lib)\n'; FAILS=$((FAILS+1))
fi

echo ""
echo "Behavioral hook tests (real branches, isolated temp repos):"
HROOT="$PWD"

# commit-on-stop: a dirty tree → exactly one checkpoint commit + a .last-changed breadcrumb.
behav_commit() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/.claude/lib"
  cp "$HROOT/.claude/hooks/commit-on-stop.sh" "$t/.claude/hooks/" && cp "$HROOT/.claude/lib/_secret-scan.sh" "$t/.claude/lib/" || exit 22
  cd "$t" || exit 21
  git init -q && git config user.email t@t.t && git config user.name t
  echo 'x = 1' > a.py && git add -A && git commit -qm init
  echo 'y = 2' >> a.py
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" bash .claude/hooks/commit-on-stop.sh >/dev/null 2>&1
  [ "$(git log --oneline | grep -c .)" = 2 ] || exit 1
  [ -f .claude/.last-changed ] || exit 2
  exit 0
)
if behav_commit; then pass "commit-on-stop: dirty tree → one checkpoint commit + breadcrumb"; else fail "commit-on-stop checkpoint behavior (rc=$?)"; fi

# commit-on-stop: a staged secret → abort, NO commit, NO stale breadcrumb (fail-closed).
behav_commit_secret() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/.claude/lib"
  cp "$HROOT/.claude/hooks/commit-on-stop.sh" "$t/.claude/hooks/" && cp "$HROOT/.claude/lib/_secret-scan.sh" "$t/.claude/lib/" || exit 22
  cd "$t" || exit 21
  git init -q && git config user.email t@t.t && git config user.name t
  echo 'ok = 1' > a.py && git add -A && git commit -qm init
  printf 'AWS = "AKIAIOSFODNN7EXAMPLE"\n' > leak.py
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" bash .claude/hooks/commit-on-stop.sh >/dev/null 2>&1
  [ "$(git log --oneline | grep -c .)" = 1 ] || exit 1   # still just the init commit
  [ ! -f .claude/.last-changed ] || exit 2               # no breadcrumb on abort
  exit 0
)
if behav_commit_secret; then pass "commit-on-stop: staged secret → abort, no commit, no breadcrumb"; else fail "commit-on-stop secret guard (rc=$?)"; fi

# steer: STEER.md present → valid additionalContext JSON keyed to the event, STEER.md consumed.
behav_steer() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  cp "$HROOT/.claude/hooks/steer.sh" "$t/" || exit 22
  cd "$t" || exit 21
  echo 'use Decimal not float for money' > STEER.md
  out=$(printf '%s' '{"hook_event_name":"PreToolUse"}' | CLAUDE_PROJECT_DIR="$t" bash steer.sh 2>/dev/null)
  printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 || exit 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("Decimal")' >/dev/null 2>&1 || exit 2
  [ ! -f STEER.md ] || exit 3                              # consumed after injecting
  exit 0
)
if behav_steer; then pass "steer: STEER.md → additionalContext JSON injected + consumed"; else fail "steer injection behavior (rc=$?)"; fi

# session-start: only real roadmap task rows are reported; blockquotes/examples are ignored.
behav_session_roadmap() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/docs"
  cp "$HROOT/.claude/hooks/session-start.sh" "$t/.claude/hooks/" || exit 22
  cd "$t" || exit 21
  git init -q && git config user.email t@t.t && git config user.name t
  cat > docs/ROADMAP.md <<'EOF'
# Roadmap
> `- [ ]` = todo, example only.
> - [ ] blockquoted example
    - [ ] real indented task
- [ ] real root task
Inline `- [ ]` example.
EOF
  out=$(CLAUDE_PROJECT_DIR="$t" bash .claude/hooks/session-start.sh 2>/dev/null)
  printf '%s\n' "$out" | grep -q 'real indented task' || exit 1
  printf '%s\n' "$out" | grep -q 'real root task' || exit 2
  printf '%s\n' "$out" | grep -q 'blockquoted example' && exit 3
  printf '%s\n' "$out" | grep -q 'todo, example only' && exit 4
  printf '%s\n' "$out" | grep -q 'Inline `- \[ \]` example' && exit 5
  exit 0
)
if behav_session_roadmap; then pass "session-start: open roadmap extraction ignores examples/blockquotes"; else fail "session-start roadmap extraction (rc=$?)"; fi

# session-start: NEXT_FINDINGS.md is capped in hot-path context and points to the full file.
behav_session_findings_cap() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/docs"
  cp "$HROOT/.claude/hooks/session-start.sh" "$t/.claude/hooks/" || exit 22
  cd "$t" || exit 21
  git init -q && git config user.email t@t.t && git config user.name t
  i=1
  while [ "$i" -le 80 ]; do printf 'finding line %02d\n' "$i"; i=$((i+1)); done > NEXT_FINDINGS.md
  out=$(CLAUDE_PROJECT_DIR="$t" bash .claude/hooks/session-start.sh 2>/dev/null)
  printf '%s\n' "$out" | grep -q 'NEXT_FINDINGS.md; showing last 60 lines' || exit 1
  printf '%s\n' "$out" | grep -q 'finding line 80' || exit 2
  printf '%s\n' "$out" | grep -q 'finding line 01' && exit 3
  printf '%s\n' "$out" | grep -q 'read NEXT_FINDINGS.md for the full findings' || exit 4
  exit 0
)
if behav_session_findings_cap; then pass "session-start: NEXT_FINDINGS.md output is capped with file pointer"; else fail "session-start findings cap (rc=$?)"; fi

# format-on-edit: reformats a messy .py without changing its meaning (skipped if ruff absent).
behav_format() (
  set -uo pipefail
  command -v ruff >/dev/null 2>&1 || exit 42
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  cp "$HROOT/.claude/hooks/format-on-edit.sh" "$t/" || exit 22
  cd "$t" || exit 21
  printf 'def f( x ):\n    return  x+1\n' > messy.py
  before=$(cat messy.py)
  printf '{"tool_input":{"file_path":"%s/messy.py"}}' "$t" | CLAUDE_PROJECT_DIR="$t" bash format-on-edit.sh >/dev/null 2>&1
  [ "$before" != "$(cat messy.py)" ] || exit 1            # whitespace changed
  { grep -q 'def f' messy.py && grep -q 'return' messy.py; } || exit 2   # meaning preserved
  exit 0
)
if behav_format; then pass "format-on-edit: reformats a .py (whitespace only, meaning preserved)"
elif [ "$?" = 42 ]; then printf '  ⊘ format-on-edit: skipped (ruff not installed)\n'
else fail "format-on-edit formatting behavior"; fi

# test-gate: block→exit2+passed:false on red; warn→exit0+passed:false; off→no run; block+green→passed:true.
behav_testgate() (
  set -uo pipefail
  t=$(mktemp -d) || exit 20; trap 'rm -rf "$t"' EXIT
  mkdir -p "$t/.claude/hooks" "$t/.claude/lib"
  cp "$HROOT/.claude/hooks/test-gate.sh" "$t/.claude/hooks/" && cp "$HROOT/.claude/lib/_test-cmd.sh" "$t/.claude/lib/" || exit 22
  cd "$t" || exit 21
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" LEAN_TEST_GATE=block LEAN_TEST_CMD=false bash .claude/hooks/test-gate.sh >/dev/null 2>&1; [ "$?" = 2 ] || exit 1
  [ "$(jq -r .passed test-results.json)" = false ] || exit 2
  rm -f test-results.json
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" LEAN_TEST_GATE=warn LEAN_TEST_CMD=false bash .claude/hooks/test-gate.sh >/dev/null 2>&1; [ "$?" = 0 ] || exit 3
  [ "$(jq -r .passed test-results.json)" = false ] || exit 4
  rm -f test-results.json
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" LEAN_TEST_GATE=off LEAN_TEST_CMD=false bash .claude/hooks/test-gate.sh >/dev/null 2>&1; [ "$?" = 0 ] || exit 5
  [ ! -f test-results.json ] || exit 6                      # off mode runs nothing
  printf '%s' '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$t" LEAN_TEST_GATE=block LEAN_TEST_CMD=true bash .claude/hooks/test-gate.sh >/dev/null 2>&1; [ "$?" = 0 ] || exit 7
  [ "$(jq -r .passed test-results.json)" = true ] || exit 8
  exit 0
)
if behav_testgate; then pass "test-gate: block exit2 on red, warn exit0, off no-run, block+green pass"; else fail "test-gate mode behavior (rc=$?)"; fi

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All hook smoke + behavioral tests passed."; exit 0
else echo "$FAILS hook test(s) failed."; exit 1; fi
