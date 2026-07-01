#!/usr/bin/env bash
# test-lint.sh — covers the Phase 8 polish helpers: scripts/next-adr.sh (deterministic ADR
# numbering + collision guard) and scripts/lint-roadmap.sh (Done-when lint).
set -uo pipefail
SCAFFOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXT_ADR="$SCAFFOLD/scripts/next-adr.sh"
LINT="$SCAFFOLD/scripts/lint-roadmap.sh"
for f in "$NEXT_ADR" "$LINT"; do [ -f "$f" ] || { echo "test: missing $f" >&2; exit 1; }; done

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-lint)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

mkrepo() {
  REPO="$WORK/$1"; rm -rf "$REPO"; mkdir -p "$REPO/scripts" "$REPO/docs"
  cp "$NEXT_ADR" "$REPO/scripts/"; cp "$LINT" "$REPO/scripts/"
  ( cd "$REPO" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -q -m init )
}

echo "next-adr tests"; echo ""
mkrepo a1
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "001" ] && pass "next-adr: empty dir → 001" || fail "next-adr empty wrong"
mkrepo a2; mkdir -p "$REPO/docs/decisions"; : > "$REPO/docs/decisions/ADR-001-x.md"; : > "$REPO/docs/decisions/ADR-002-y.md"
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "003" ] && pass "next-adr: highest+1 (003)" || fail "next-adr increment wrong"
mkrepo a3; mkdir -p "$REPO/docs/decisions"; : > "$REPO/docs/decisions/ADR-007-z.md"
[ "$( cd "$REPO" && bash scripts/next-adr.sh )" = "008" ] && pass "next-adr: respects zero-padding gaps (008)" || fail "next-adr padding wrong"

echo ""
echo "lint-roadmap tests"; echo ""
mkrepo l1
printf '## Phase 1 — A\n- [ ] t\nDone when: the suite is green\n\n## Phase 2 — B\n- [ ] u\nDone when: builds clean\n' > "$REPO/docs/ROADMAP.md"
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && pass "lint-roadmap: all phases have Done when → exit 0" || fail "lint-roadmap false-positived on a good roadmap"
mkrepo l2
printf '## Phase 1 — A\n- [ ] t\nDone when: ok\n\n## Phase 2 — B\n- [ ] u\n' > "$REPO/docs/ROADMAP.md"   # phase 2 missing Done when
( cd "$REPO" && bash scripts/lint-roadmap.sh --strict ) >/dev/null 2>&1 && fail "lint-roadmap missed a phase with no Done when" || pass "lint-roadmap: missing Done when → --strict exit 1"
out=$( cd "$REPO" && bash scripts/lint-roadmap.sh ); rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Phase 2'; } && pass "lint-roadmap: advisory mode warns but exits 0" || fail "lint-roadmap advisory mode wrong (rc=$rc)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All lint/helper tests passed."; exit 0
else echo "$FAILS lint test(s) FAILED."; exit 1; fi
