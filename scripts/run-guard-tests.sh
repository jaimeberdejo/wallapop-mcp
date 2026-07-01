#!/usr/bin/env bash
# run-guard-tests.sh — the single behavioral-guard test list, run by BOTH CI workflows
# (root .github/workflows/ci.yml and the shipped lean-stack/.github/workflows/lean-stack-ci.yml)
# and by anyone locally. Having ONE list here removes the two hand-maintained copies that used to
# drift between the workflows. Ships with the scaffold (install.sh copies scripts/), so the shipped
# workflow stays self-contained.
#
# No `claude` CLI needed — every test here runs offline against the shell gates.
# Fail-fast: the first red test aborts with its exit code.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Git identity: the tests spin up throwaway repos that need a committer. Set a CI identity
# ONLY if the environment has none — never clobber a developer's existing global config.
git config --global user.email >/dev/null 2>&1 || git config --global user.email ci@example.com
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  ci

# Hooks/scripts must be executable (fresh checkouts may drop the bit).
chmod +x .claude/hooks/*.sh scripts/*.sh 2>/dev/null || true

TESTS=(
  test-hooks.sh
  test-high-stakes.sh
  test-secret-scan.sh
  test-checkpoint.sh
  test-autopilot-gates.sh
  test-tick.sh
  test-docs-invariants.sh
  test-close-milestone.sh
  test-doctor.sh
  test-lint.sh
)

# Drift guard: every scripts/test-*.sh MUST be listed above, or a newly-added guard test would
# silently never run in CI — the exact failure this single-source runner exists to prevent.
# (test-evidence.sh is excluded: it is the evidence PRODUCER, not a test suite.)
for f in scripts/test-*.sh; do
  [ -e "$f" ] || continue
  b="${f#scripts/}"
  [ "$b" = "test-evidence.sh" ] && continue
  case " ${TESTS[*]} " in
    *" $b "*) ;;
    *) echo "run-guard-tests: '$b' exists but is missing from TESTS[] — add it (or it never runs in CI)."; exit 1 ;;
  esac
done

for t in "${TESTS[@]}"; do
  echo "=== scripts/$t ==="
  bash "scripts/$t"
done

echo "All guard tests passed."
