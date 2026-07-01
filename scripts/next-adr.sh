#!/usr/bin/env bash
# next-adr.sh — print the next zero-padded ADR number for docs/decisions/, so ADR numbering is
# deterministic instead of eyeballed (the audit flagged "two ADR-005 files possible"). The `adr`
# skill calls this instead of guessing. Refuses (exit 1) if the computed number somehow already
# exists. Usage: bash scripts/next-adr.sh   ->  e.g. "004"
set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1
DIR="docs/decisions"
mkdir -p "$DIR"

max=0
for f in "$DIR"/ADR-*.md; do
  [ -e "$f" ] || continue
  n=$(basename "$f" | sed -nE 's/^ADR-0*([0-9]+).*/\1/p')
  [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
done

printf -v padded '%03d' "$((max + 1))"
if ls "$DIR"/ADR-"$padded"-*.md "$DIR"/ADR-"$padded".md >/dev/null 2>&1; then
  echo "next-adr: ADR-$padded already exists — numbering collision, resolve manually." >&2
  exit 1
fi
printf '%s\n' "$padded"
