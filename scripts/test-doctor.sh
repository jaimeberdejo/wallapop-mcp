#!/usr/bin/env bash
# test-doctor.sh — doctor.sh --fix must apply only SAFE, LOCAL, IDEMPOTENT repairs (chmod +x,
# docs/plans, docs/FAILURES.md), never touch the high-stakes fingerprint, and be a no-op on a
# second run. Installs the scaffold into a throwaway repo and breaks the fixable things.
set -uo pipefail
SC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }

FAILS=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1"; FAILS=$((FAILS+1)); }

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t leanstack-doc)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
REPO="$WORK/proj"; mkdir -p "$REPO"
cp -R "$SC/." "$REPO/"
cd "$REPO" || exit 1
git init -q && git config user.email t@t.t && git config user.name t
chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null
git add -A >/dev/null 2>&1 && git commit -q -m init

echo "doctor --fix tests"; echo ""

# Break the fixable things; plant a fingerprint to confirm --fix never edits it.
chmod -x .claude/hooks/session-start.sh
rm -rf docs/plans docs/FAILURES.md
printf 'HIGH_STAKES_RE=SENTINEL_DO_NOT_TOUCH\n' > .claude/.high-stakes-default
fp_before=$(cat .claude/.high-stakes-default)

bash scripts/doctor.sh --fix > "$WORK/out" 2>&1 || true

[ -x .claude/hooks/session-start.sh ] && pass "--fix restores the executable bit on a hook" || fail "hook not made executable"
[ -d docs/plans ] && pass "--fix creates docs/plans/" || fail "docs/plans not created"
[ -f docs/FAILURES.md ] && pass "--fix creates docs/FAILURES.md" || fail "docs/FAILURES.md not created"
[ "$fp_before" = "$(cat .claude/.high-stakes-default)" ] && pass "--fix leaves the high-stakes fingerprint untouched" || fail "fingerprint was modified"
grep -q "fixed:" "$WORK/out" && pass "--fix reports what it repaired" || fail "--fix reported no repairs"

# Idempotent: a second --fix finds nothing left to repair.
bash scripts/doctor.sh --fix > "$WORK/out2" 2>&1 || true
grep -q "fixed:" "$WORK/out2" && fail "second --fix still repairs (not idempotent)" || pass "second --fix is a no-op (idempotent)"

# Plain doctor.sh stays report-only (does not create files).
rm -rf docs/plans
bash scripts/doctor.sh > /dev/null 2>&1 || true
[ ! -d docs/plans ] && pass "plain doctor.sh stays report-only (no repairs)" || fail "plain doctor.sh mutated the tree"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "All doctor --fix tests passed."; exit 0
else echo "$FAILS doctor test(s) FAILED."; tail -n 15 "$WORK/out" 2>/dev/null; exit 1; fi
