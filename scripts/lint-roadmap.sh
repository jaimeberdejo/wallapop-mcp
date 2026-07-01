#!/usr/bin/env bash
# lint-roadmap.sh — dependency-free check that every "## Phase" in docs/ROADMAP.md carries a
# non-empty "Done when:" line (the evaluator grades against it; a phase without one is unbuildable).
# Advisory by default (exit 0, prints warnings); --strict exits 1 on any problem.
# Usage: bash scripts/lint-roadmap.sh [--strict] [path-to-roadmap]
set -uo pipefail
STRICT=0; FILE="docs/ROADMAP.md"
for a in "$@"; do case "$a" in --strict) STRICT=1 ;; *) FILE="$a" ;; esac; done
[ -f "$FILE" ] || { echo "lint-roadmap: no $FILE — nothing to lint."; exit 0; }

OUT=$(awk '
  function flush() { if (tracking && !dw) { printf "  ! missing \"Done when:\" — %s\n", h; miss++ } }
  /^## Phase/ { flush(); h=$0; dw=0; tracking=1; next }
  /^## /      { flush(); tracking=0; next }
  /^[[:space:]]*Done when:/ && tracking {
    v=$0; sub(/^[[:space:]]*Done when:[[:space:]]*/, "", v)
    if (v == "") { printf "  ! empty \"Done when:\" — %s\n", h; miss++ } else dw=1
  }
  END { flush(); exit (miss > 0 ? 1 : 0) }
' "$FILE")
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "lint-roadmap: every phase has a Done when: line."
  exit 0
fi
printf '%s\n' "$OUT"
if [ "$STRICT" -eq 1 ]; then echo "lint-roadmap: problems found (--strict)."; exit 1; fi
echo "lint-roadmap: warnings above (advisory; pass --strict to fail)."
exit 0
