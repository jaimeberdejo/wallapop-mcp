#!/usr/bin/env bash
# autopilot.sh — fresh-context autonomous loop with guardrails.
#
# Runs roadmap phases one at a time, each in a FRESH claude process (so context
# never rots), grading each with an INDEPENDENT evaluator process before ticking.
# The SCRIPT is the sole roadmap-ticker — the builder never marks its own work done.
# State persists in docs/ + git between iterations.
#
# Usage:
#   bash scripts/autopilot.sh [COUNT] [--allow-dirty] [--no-worktree] [--pr]
#     COUNT can be:
#       N         run up to N phases   (e.g. 5  → "only 5")
#       N-M       run up to M phases, aiming for at least N  (e.g. 3-5 → "from 3 to 5")
#       all|max   run until the roadmap is empty or a guardrail trips (capped at 50 for safety)
#       (omitted) default 15
#     Malformed counts (e.g. 5x, 3-) are rejected, not silently ignored.
#     --no-worktree    run IN-PLACE in the current checkout instead of an isolated
#                      worktree. Isolation is the DEFAULT (a bad run can't touch your
#                      main checkout); pass this only when you accept that risk.
#     --pr             on finish, push the branch and open a PR with `gh` (only meaningful
#                      with the default worktree; nothing is ever pushed to your current
#                      branch). A secret-scan gate runs before any push.
#     --allow-dirty    skip the clean-tree preflight (commit/stash is otherwise required)
# Stop:    touch AGENT_STOP
# Steer:   echo "use Decimal not float for money" > STEER.md
#
# Guardrails: preflight, max iterations, kill-switch, fresh context per loop,
# independent evaluator with STRICT verdict parsing + evaluator-change cleanup,
# per-phase thrash cap, the script as sole ticker, high-stakes gate, shared
# secret-scan before commit/push, default worktree isolation. Set a budget cap in
# your Claude Code / gateway config as the authoritative outer backstop on real cost.

set -uo pipefail

MAX_ITER=15
MIN_TARGET=0
UNBOUNDED=0
ALLOW_DIRTY=0
USE_WORKTREE=1         # isolation is the DEFAULT; --no-worktree opts out
OPEN_PR=0
HS_BLOCKED=0          # set to 1 if a high-stakes phase tripped the gate (never push it)
for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ; continue ;;
    --worktree)    USE_WORKTREE=1 ; continue ;;            # explicit (already the default)
    --no-worktree) USE_WORKTREE=0 ; continue ;;            # opt out of isolation
    --pr)          OPEN_PR=1 ; continue ;;
    all|max|ALL|MAX) MAX_ITER=50; UNBOUNDED=1 ; continue ;;  # advance as much as you can
  esac
  # Numeric COUNT forms — anchored validation; reject malformed loudly (no silent ignore).
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    MAX_ITER="$arg"
  elif [[ "$arg" =~ ^[0-9]+-[0-9]+$ ]]; then
    MIN_TARGET="${arg%%-*}"; MAX_ITER="${arg##*-}"
  else
    echo "autopilot: unrecognized argument '$arg'." >&2
    echo "  expected: N | N-M | all | --no-worktree | --worktree | --allow-dirty | --pr" >&2
    exit 1
  fi
done

# Default the test gate ON for headless runs so each turn writes test-results.json
# evidence (the test-gate.sh Stop hook reads $LEAN_TEST_GATE). Set it to `block`
# to hard-fail on failing/missing tests, or `off` to disable the gate entirely.
export LEAN_TEST_GATE="${LEAN_TEST_GATE:-warn}"

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

# Original repo root, captured BEFORE any --worktree cd. Operators are told to
# `touch AGENT_STOP` (or write STEER.md) in their original checkout, so the loop's
# stop checks must look here as well as in the (possibly worktree) working dir.
# Defined unconditionally so the checks work whether or not the worktree is used.
ORIG_ROOT="$PWD"

# ----------------------------- preflight -----------------------------
fail() { echo "autopilot: PREFLIGHT FAILED — $1" >&2; exit 1; }

# ---- single-run lock + cleanup trap ----
# Prevent two autopilots from racing the same checkout, and never leave a stale lock or silently
# orphan a worktree. The lock lives in the ORIGINAL checkout (the worktree is per-run).
LOCK="$ORIG_ROOT/.claude/.autopilot.lock"
LOCK_HELD=0
cleanup_on_exit() {
  local rc=$?
  [ "$LOCK_HELD" -eq 1 ] && rm -f "$LOCK" 2>/dev/null
  # Abnormal exit (signal / error) AFTER a worktree was created: do NOT auto-remove it — it may
  # hold unpushed or high-stakes commits. Point the operator at it instead.
  if [ "$rc" -ne 0 ] && [ "${USE_WORKTREE:-0}" -eq 1 ] && [ -n "${WT_DIR:-}" ] && [ -d "${WT_DIR:-/nonexistent}" ]; then
    echo "autopilot: ⚠ exited early (rc $rc); worktree left for inspection: $WT_DIR" >&2
    echo "autopilot:   review it, then remove with: git worktree remove \"$WT_DIR\" (add --force to discard)." >&2
  fi
}
trap cleanup_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$ORIG_ROOT/.claude" 2>/dev/null || true
# Atomic acquire: `set -o noclobber` makes `>` fail if the file already exists (O_EXCL), so two
# simultaneous launches can't both win the check-then-write race.
if ( set -o noclobber; echo "$$" > "$LOCK" ) 2>/dev/null; then
  LOCK_HELD=1
else
  OLDPID=$(head -1 "$LOCK" 2>/dev/null)
  if [ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null; then
    fail "another autopilot run is active (pid $OLDPID; lock $LOCK). Wait for it, or remove the lock if you're certain it's dead."
  fi
  echo "autopilot: stale lock from dead pid ${OLDPID:-?} — reclaiming."
  rm -f "$LOCK"
  if ( set -o noclobber; echo "$$" > "$LOCK" ) 2>/dev/null; then
    LOCK_HELD=1
  else
    fail "could not acquire lock $LOCK (racing another run?)."
  fi
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git repository (run 'git init')."
command -v claude >/dev/null 2>&1 || fail "'claude' CLI not found on PATH."
command -v jq     >/dev/null 2>&1 || fail "'jq' not found (hooks need it)."
[ -f .claude/settings.json ] || fail "missing .claude/settings.json."
[ -f docs/ROADMAP.md ]       || fail "missing docs/ROADMAP.md."
[ -f docs/STATE.md ]         || fail "missing docs/STATE.md."

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  fail "working tree is dirty. Commit/stash first, or pass --allow-dirty."
fi
if [ "$OPEN_PR" -eq 1 ] && ! command -v gh >/dev/null 2>&1; then
  fail "--pr requested but 'gh' (GitHub CLI) is not installed."
fi
if ! grep -q "\- \[ \]" docs/ROADMAP.md 2>/dev/null; then
  echo "autopilot: roadmap has no open items. Nothing to do."; exit 0
fi

# ----------------------- worktree isolation (default ON) -----------------------
BRANCH=""
if [ "$USE_WORKTREE" -eq 1 ]; then
  STAMP=$(date +%Y%m%d-%H%M%S)
  BRANCH="autopilot/$STAMP"
  WT_DIR="$(cd .. && pwd)/$(basename "$PWD")-autopilot-$STAMP"
  echo "autopilot: creating isolated worktree → $WT_DIR (branch $BRANCH)"
  git worktree add -b "$BRANCH" "$WT_DIR" HEAD >/dev/null 2>&1 || fail "could not create worktree."
  cd "$WT_DIR" || fail "could not enter worktree."
else
  echo "autopilot: ⚠ running IN-PLACE in your current checkout ($PWD)."
  echo "autopilot:   a runaway loop can mutate the files you're working on. Isolation is the"
  echo "autopilot:   default (--worktree, a throwaway branch); you opted out with --no-worktree."
fi

# Baseline commit for the push-gate: secrets must not enter the remote even though
# the builder's per-task commits never pass through the Stop-hook secret guard.
START_REF=$(git rev-parse HEAD 2>/dev/null)

chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null || true

# Source the SHARED guard libraries now that the final working dir is set. These
# are installed into every project; if absent we warn LOUDLY (the matching gate is
# then disabled — better to know than to silently skip a safety check).
if [ -f .claude/lib/_secret-scan.sh ]; then
  . .claude/lib/_secret-scan.sh 2>/dev/null || true
else
  echo "autopilot: WARNING — .claude/lib/_secret-scan.sh not found; commit/push secret-gate DISABLED." >&2
fi
if [ -f .claude/lib/_high-stakes.sh ]; then
  . .claude/lib/_high-stakes.sh 2>/dev/null || true
else
  echo "autopilot: WARNING — .claude/lib/_high-stakes.sh not found; high-stakes gate DISABLED." >&2
fi

if [ "$UNBOUNDED" -eq 1 ]; then
  echo "autopilot: advancing until the roadmap is empty (safety cap $MAX_ITER). touch AGENT_STOP to halt."
elif [ "$MIN_TARGET" -gt 0 ]; then
  echo "autopilot: aiming for $MIN_TARGET–$MAX_ITER phases (hard cap $MAX_ITER). touch AGENT_STOP to halt."
else
  echo "autopilot: up to $MAX_ITER iterations. touch AGENT_STOP to halt."
fi

# Roadmap ticking + ALL completion gates (evidence freshness, secret scan, high-stakes,
# and — in Phase 2B — the STATE machine block) now live in the SHARED scripts/tick.sh,
# called below on a PASS. The in-session /wrap path calls the same script, so no command,
# prompt, or model can mark roadmap work done without passing the identical gate.

# Decision A — discard any file changes the EVALUATOR made before trusting its
# verdict (so a grader that edits code into passing can't influence the ticked tree).
# Pre-grade the builder has already committed its work, so the tracked tree is
# normally clean ($PRE_SNAP empty). If it was dirty we can't tell builder vs
# evaluator changes apart → STOP. Removes ONLY untracked files the evaluator created
# (absent in $PRE_UNTRACKED); never deletes a pre-existing user untracked file.
cleanup_eval_changes() {
  if [ -n "$PRE_SNAP" ]; then
    echo "autopilot: tracked tree was dirty before grading — can't isolate evaluator changes (ambiguous). STOPPING." >&2
    return 1
  fi
  # The grader must not influence the ticked tree. If it COMMITTED (HEAD moved), that's a
  # contract violation: undo the commit(s) and STOP — never tick a tree the grader altered.
  local now_head; now_head=$(git rev-parse HEAD 2>/dev/null)
  if [ -n "$PRE_GRADE_HEAD" ] && [ "$now_head" != "$PRE_GRADE_HEAD" ]; then
    git reset -q --hard "$PRE_GRADE_HEAD" 2>/dev/null || true
    echo "autopilot: evaluator COMMITTED during grading (HEAD moved $PRE_GRADE_HEAD → $now_head) — reverted and STOPPING (grader must not alter the tree)." >&2
    return 1
  fi
  git reset -q --hard HEAD 2>/dev/null || true      # revert any tracked edits (tree was clean → safe)
  local post new
  post=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  new=$(comm -13 <(printf '%s\n' "$PRE_UNTRACKED") <(printf '%s\n' "$post"))
  if [ -n "$new" ]; then
    printf '%s\n' "$new" | while IFS= read -r f; do [ -n "$f" ] && rm -f -- "$f"; done
  fi
  # Verify we restored the pre-grade state EXACTLY; if not, STOP (never tick on an
  # uncertain tree).
  if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    echo "autopilot: could not restore tracked tree after grading — STOPPING." >&2; return 1
  fi
  local post2
  post2=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  if [ "$post2" != "$PRE_UNTRACKED" ]; then
    echo "autopilot: untracked file set differs from pre-grade after cleanup — STOPPING." >&2; return 1
  fi
  return 0
}

PREV_OPEN_SIGNATURE=""
SAME_PHASE_FAILS=0
MAX_SAME_PHASE_FAILS=3

for i in $(seq 1 "$MAX_ITER"); do
  # Kill-switch: present in the worktree working dir OR the operator's original checkout.
  if [ -f AGENT_STOP ] || [ -f "$ORIG_ROOT/AGENT_STOP" ]; then
    echo "autopilot: AGENT_STOP present — stopping at iteration $i."; break
  fi
  grep -q "\- \[ \]" docs/ROADMAP.md 2>/dev/null || { echo "autopilot: roadmap complete. Done."; break; }

  # STEER mirror: operators write STEER.md in their ORIGINAL checkout, but the loop
  # runs in the worktree. Move it in so the builder (which reads ./STEER.md) sees it.
  if [ "$PWD" != "$ORIG_ROOT" ] && [ -f "$ORIG_ROOT/STEER.md" ]; then
    mv "$ORIG_ROOT/STEER.md" ./STEER.md 2>/dev/null || true
  fi

  OPEN_SIGNATURE=$(grep -n "\- \[ \]" docs/ROADMAP.md 2>/dev/null | { md5 2>/dev/null || md5sum 2>/dev/null; })

  echo ""; echo "=== iteration $i / $MAX_ITER ==="

  # Builder: fresh context, builds ONE phase, does NOT tick the roadmap.
  if ! claude -p "/phase" --permission-mode acceptEdits 2>&1 | tee -a autopilot.log; then
    echo "autopilot: builder process exited non-zero — stopping." | tee -a autopilot.log; break
  fi

  # Produce AUTHORITATIVE tick evidence now that the builder has fully exited and HEAD is
  # final. The Stop-hook test-gate is advisory and races commit-on-stop (which advances HEAD
  # past any sha a Stop-time gate stamped), so it cannot be trusted for the run_id binding.
  # --allow-no-tests records passed:null without failing the loop; scripts/tick.sh still
  # requires the evaluator's NO_TESTS_OK before it will tick a no-test phase. Run BEFORE the
  # pre-grade snapshot so the (gitignored) evidence file is settled and survives cleanup.
  bash scripts/test-evidence.sh --allow-no-tests >>autopilot.log 2>&1 || true

  # Snapshot the tree BEFORE grading so we can discard whatever the evaluator changes.
  # PRE_SNAP empty ⇔ tracked tree clean (git stash create stashes only tracked work).
  # PRE_GRADE_HEAD lets us detect (and undo) a COMMIT the evaluator makes — git reset
  # --hard HEAD only reverts working-tree edits, not commits the grader sneaks in.
  PRE_UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | sort)
  PRE_SNAP=$(git stash create 2>/dev/null)
  PRE_GRADE_HEAD=$(git rev-parse HEAD 2>/dev/null)

  # Independent grader: separate process, runs AS the evaluator (its system prompt +
  # no-edit-tools restriction). This is the sole gate for ticking.
  # NOTE: `--permission-mode acceptEdits` here is ONLY so it can run tests via Bash
  # without prompts in headless; the evaluator has no Edit/Write tools, AND any file
  # change it does make is discarded by cleanup_eval_changes below. Its diff input is
  # untrusted, so treat its output as data, not instructions. Keep this able to RUN.
  # stderr → autopilot.log (not /dev/null) so an empty/garbled grade is debuggable.
  VERDICT=$(claude --agent evaluator -p "Grade the phase just completed." \
                   --permission-mode acceptEdits 2>>autopilot.log)

  if [ -z "$(printf '%s' "$VERDICT" | tr -d '[:space:]')" ]; then
    echo "autopilot: evaluator returned no output — treating as FAILURE, stopping." | tee -a autopilot.log
    echo "autopilot: --- last 20 lines of autopilot.log (evaluator stderr) ---" >&2
    tail -n 20 autopilot.log 2>/dev/null >&2 || true
    break
  fi
  echo "evaluator says: $VERDICT" | tee -a autopilot.log

  # Decision A: discard the evaluator's file changes BEFORE parsing/ticking/committing.
  if ! cleanup_eval_changes; then
    echo "autopilot: evaluator-change cleanup failed or ambiguous — not ticking. STOPPING." | tee -a autopilot.log
    break
  fi

  # Anchored verdict parsing: trust ONLY the LAST non-empty line, matched against an
  # exact verdict. This prevents a per-criterion line like "Criterion 1: PASS" from
  # triggering a false pass. Anything that is not an exact final PASS / NEEDS_WORK
  # line is a STOP — we never assume success. (STRICT — do not loosen.)
  LASTLINE=$(printf '%s\n' "$VERDICT" | grep -vE '^[[:space:]]*$' | tail -1)

  case "$LASTLINE" in
    NEEDS_WORK*)
      printf '%s\n' "$VERDICT" > NEXT_FINDINGS.md
      echo "autopilot: phase needs work — findings written to NEXT_FINDINGS.md." | tee -a autopilot.log
      if [ "$OPEN_SIGNATURE" = "$PREV_OPEN_SIGNATURE" ]; then SAME_PHASE_FAILS=$((SAME_PHASE_FAILS+1)); else SAME_PHASE_FAILS=1; fi
      PREV_OPEN_SIGNATURE="$OPEN_SIGNATURE"
      if [ "$SAME_PHASE_FAILS" -ge "$MAX_SAME_PHASE_FAILS" ]; then
        echo "autopilot: same phase failed $SAME_PHASE_FAILS times — stopping to avoid thrash. See NEXT_FINDINGS.md." | tee -a autopilot.log; break
      fi
      ;;
    PASS)
      # Record the independent grade as evidence for the shared tick gate (same writer the
      # in-session /wrap path uses, so the grade-file format has one source). run_id binds it to
      # the exact commit; NO_TESTS_OK (only if the grader emitted it) authorizes ticking a phase
      # that legitimately has no test suite.
      bash scripts/record-grade.sh "$VERDICT" >>autopilot.log 2>&1

      # Route through the SINGLE completion gate. tick.sh verifies the evidence (grade + fresh
      # green tests bound to HEAD), secret-scans the whole phase diff, blocks high-stakes paths,
      # updates the STATE machine block, and only then flips the checkbox — the SAME gate /wrap
      # uses. It reads its inputs from the filesystem and committed history, so nothing needs
      # staging beforehand; we stage + commit the resulting roadmap/STATE change only on success.
      PHASE_HEADING=$(cat .claude/.phase-ready 2>/dev/null || echo "phase")   # tick.sh consumes .phase-ready
      bash scripts/tick.sh 2>&1 | tee -a autopilot.log
      TICK_RC="${PIPESTATUS[0]}"
      case "$TICK_RC" in
        0)
          # Persist the resolved failure trail (don't just delete it): a phase that needed work
          # before passing leaves a record in docs/FAILURES.md so recurring blockers are visible.
          if [ -f NEXT_FINDINGS.md ]; then
            {
              echo ""
              echo "## ${PHASE_HEADING#\#\# } — resolved $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
              cat NEXT_FINDINGS.md
            } >> docs/FAILURES.md
            rm -f NEXT_FINDINGS.md
          fi
          git add -A 2>/dev/null
          git commit -m "autopilot: phase passed independent grade (iteration $i)" >/dev/null 2>&1 || true
          SAME_PHASE_FAILS=0; PREV_OPEN_SIGNATURE=""
          ;;
        3)
          HS_BLOCKED=1   # high-stakes: finish block must NOT push this branch, even with --pr
          echo "autopilot: ⛔ HIGH-STAKES phase — finish it SUPERVISED. Branch stays LOCAL (no push even with --pr)." | tee -a autopilot.log
          break
          ;;
        *)
          git reset -q 2>/dev/null || true
          echo "autopilot: tick gate REFUSED (rc $TICK_RC) — not ticking. See NEXT_FINDINGS.md / autopilot.log. STOPPING." | tee -a autopilot.log
          break
          ;;
      esac
      ;;
    *)
      echo "autopilot: unrecognized verdict (final line: '$LASTLINE') — stopping (won't assume success)." | tee -a autopilot.log; break
      ;;
  esac
done

# ----------------------------- finish / PR -----------------------------
if [ "$HS_BLOCKED" -eq 1 ]; then
  # A high-stakes phase tripped the gate. The builder's per-task commits are already
  # in this branch, but high-stakes work is human-on-the-loop: it is NEVER auto-pushed,
  # even with --pr. Leave the branch local for supervised review.
  echo "autopilot: high-stakes phase reached — branch $BRANCH stays LOCAL for supervised review (not pushed)." | tee -a autopilot.log
  if [ "$USE_WORKTREE" -eq 1 ]; then
    echo "autopilot: review it in $PWD, then merge or 'git worktree remove' when finished."
  fi
elif [ "$USE_WORKTREE" -eq 1 ] && [ "$OPEN_PR" -eq 1 ]; then
  # Push-gate: the builder's per-task commits never passed through the Stop-hook
  # secret guard, so scan the WHOLE range before anything reaches the remote.
  if type -t secret_scan_diff >/dev/null 2>&1; then
    PUSH_FINDINGS=$(secret_scan_diff "${START_REF:-HEAD~1}..HEAD"); PUSH_RC=$?
    if [ "$PUSH_RC" -ne 0 ]; then
      echo "autopilot: ⛔ SECRET GUARD — commit range contains a secret. NOT pushing / no PR." >&2
      printf '%s\n' "$PUSH_FINDINGS" >&2
      echo "autopilot: branch $BRANCH stays local — clean the history before pushing." >&2
      exit 1
    fi
  fi
  echo "autopilot: pushing $BRANCH and opening a PR..."
  if git push -u origin "$BRANCH" >/dev/null 2>&1; then
    gh pr create --fill --title "autopilot: $BRANCH" 2>&1 | tee -a autopilot.log || echo "autopilot: gh pr create failed — open it manually."
  else
    echo "autopilot: git push failed (no remote / auth?). Branch $BRANCH is local; review and push manually."
  fi
elif [ "$USE_WORKTREE" -eq 1 ]; then
  echo "autopilot: done. Review branch $BRANCH in $PWD, then merge or 'git worktree remove' when finished."
fi

echo "autopilot: finished."
