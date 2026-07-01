#!/usr/bin/env bash
# test-close-milestone.sh — the milestone-closure gate must REFUSE while open items or
# unresolved findings remain, archive a finished roadmap (preserving history), scaffold a fresh
# one, reset the STATE auto-block, and be safe to re-run. Runs the REAL script in temp repos.
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOSE="$SCAFFOLD/scripts/close-milestone.sh"
[ -f "$CLOSE" ] || { echo "test: missing $CLOSE" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-ms)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

# mkrepo <name> <roadmap-body>: repo with scripts/close-milestone.sh + a STATE auto-block.
mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/scripts" "$REPO/docs"
  cp "$CLOSE" "$REPO/scripts/close-milestone.sh"
  printf '%s\n' "$2" > "$REPO/docs/ROADMAP.md"
  printf '# State\n\n## Auto status\n<!-- lean:auto:begin -->\n- something\n<!-- lean:auto:end -->\n\n## Now\nhi\n' > "$REPO/docs/STATE.md"
  printf 'NEXT_FINDINGS.md\n' > "$REPO/.gitignore"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
}
runclose() { ( cd "$1" && shift && bash scripts/close-milestone.sh "$@" ) >"$WORK/out" 2>&1; echo $?; }

DONE='## Phase 1 — Work

- [x] do the work

## Phase 2 — More

- [x] more work'
OPEN='## Phase 1 — Work

- [x] done

- [ ] still open'

echo "milestone closure tests"; echo ""

# 1 — open items → refuses, nothing archived.
mkrepo m1 "$OPEN"; rc=$(runclose "$REPO")
{ [ "$rc" = 1 ] && [ ! -d "$REPO/docs/archive" ] && [ -f "$REPO/docs/ROADMAP.md" ]; } \
  && pass "open items → refuses, roadmap not archived" || fail "open-items closure mishandled (rc=$rc)"

# 2 — all done but NEXT_FINDINGS.md present → refuses.
mkrepo m2 "$DONE"; printf 'unresolved\n' > "$REPO/NEXT_FINDINGS.md"; rc=$(runclose "$REPO")
{ [ "$rc" = 1 ] && [ ! -d "$REPO/docs/archive" ]; } \
  && pass "unresolved NEXT_FINDINGS → refuses" || fail "findings-present closure mishandled (rc=$rc)"

# 3 — all done, no findings → archives, fresh roadmap, STATE auto-block reset.
mkrepo m3 "$DONE"; rc=$(runclose "$REPO" --name v1)
arch="$REPO/docs/archive/ROADMAP-v1.md"
{ [ "$rc" = 0 ] && [ -f "$arch" ] && grep -q 'Phase 1 — Work' "$arch"; } \
  && pass "complete roadmap → archived with history" || fail "did not archive complete roadmap (rc=$rc)"
{ [ -f "$REPO/docs/ROADMAP.md" ] && ! grep -qE '\- \[[ xX]\]' "$REPO/docs/ROADMAP.md"; } \
  && pass "fresh empty roadmap created (no checkboxes)" || fail "fresh roadmap not created/clean"
grep -q 'Milestone v1 closed' "$REPO/docs/STATE.md" && pass "STATE auto-block reset to next-scope" || fail "STATE auto-block not reset"

# 4 — re-run after a close (fresh empty roadmap) → refuses 'nothing to close' (idempotent-safe).
rc=$(runclose "$REPO" --name v1)
{ [ "$rc" = 1 ] && grep -q 'nothing to close' "$WORK/out"; } \
  && pass "re-run on empty roadmap → refuses (no duplicate archive)" || fail "re-run not idempotent-safe (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All milestone closure tests passed."; exit 0
else echo "$FAILS milestone test(s) FAILED."; echo "--- last output ---"; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
