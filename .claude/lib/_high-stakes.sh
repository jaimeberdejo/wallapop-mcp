#!/usr/bin/env bash
# _high-stakes.sh — SHARED high-stakes path list + matcher (sourced, not a hook).
# Single source of truth for which paths are "high-stakes" (auth / money /
# migrations / deletes / external side effects). Used by scripts/autopilot.sh to
# REFUSE to auto-commit/tick a phase whose diff touches these paths unattended,
# and kept in sync with .claude/rules/high-stakes.md.
#
# Matching is done with grep -E (NOT shell `case`) so it behaves identically
# whether this file is sourced under bash or zsh. Edit HIGH_STAKES_RE to match
# YOUR project's sensitive paths.
#
# Segment keywords match as a path SEGMENT, bounded by `/`, a filename separator
# (`.`/`_`/`-`), or end — so they fire on directories AND single-file modules alike
# (`auth/x`, `auth.py`, `session-store.ts`). `auth[a-z0-9_-]*` covers auth / authn /
# authentication / oauth2 / auth-service. The loose substrings (delete/email/deploy/…)
# match ANYWHERE in the path. The gate fails SAFE when over-broad (a false hit just
# forces supervised review), so this list is intentionally generous — better to stop
# on a benign `discharge.py` than to miss a real `refund` path. Edit it for YOUR repo.
HIGH_STAKES_RE='(^|/)(oauth[0-9]*|auth[a-z0-9_-]*|login|sessions?|accounts?|payments?|billing|transactions?|compliance|suitability|secrets?|kyc|wallet|ledger)([/._-]|$)|migrat|money|payment|credential|delete|deletion|destroy|email|deploy|refund|withdraw|charge|webhook'

# high_stakes_match <newline-separated-paths>
#   Echoes the matching paths; returns 0 if any matched, 1 if none.
#   FAILS SAFE: if HIGH_STAKES_RE is empty or unset (a customization slip), treat EVERY
#   path as high-stakes rather than silently matching nothing (which would fail OPEN).
high_stakes_match() {
  if [ -z "${HIGH_STAKES_RE:-}" ]; then
    echo "high-stakes: HIGH_STAKES_RE is empty/unset — failing SAFE (treating all paths as high-stakes)." >&2
    printf '%s\n' "$1"; return 0
  fi
  local matched
  matched=$(printf '%s\n' "$1" | grep -Ei "$HIGH_STAKES_RE" 2>/dev/null)
  if [ -n "$matched" ]; then printf '%s\n' "$matched"; return 0; fi
  return 1
}

# --- content-level high-stakes detection ---------------------------------------
# The path matcher above is blind to destructive CONTENT in a benignly-named file (a
# DROP TABLE in src/utils.py). This is a TIGHT, high-precision list of destructive
# operations. It is a BACKSTOP, not a scanner: a false hit only forces SUPERVISED review
# (never a false PASS), so over-matching is safe; missing a novel destructive pattern is
# the residual risk. scripts/tick.sh feeds it the ADDED diff lines of a phase.
#   DROP/TRUNCATE TABLE, DELETE FROM, rm -r/-f, force-push, --no-verify, os.system(),
#   shell=True, eval(  (eval/rm are anchored so retrieval()/format don't false-hit; the eval
#   anchor also excludes a preceding '.' so method calls like model.eval() / x.eval() — common
#   and benign, e.g. PyTorch — do NOT trip it; only a bare eval( does).
HIGH_STAKES_CONTENT_RE='DROP[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM|(^|[^[:alnum:]_])rm[[:space:]]+-[a-z]*[rf]|git[[:space:]]+push[[:space:]].*--force|--no-verify|os\.system[[:space:]]*\(|shell[[:space:]]*=[[:space:]]*True|(^|[^[:alnum:]_.])eval[[:space:]]*\('

# high_stakes_content_match <text>: echoes matching lines; returns 0 if any matched, 1 if none.
high_stakes_content_match() {
  local matched
  matched=$(printf '%s\n' "$1" | grep -Ei "$HIGH_STAKES_CONTENT_RE" 2>/dev/null)
  if [ -n "$matched" ]; then printf '%s\n' "$matched"; return 0; fi
  return 1
}

return 0 2>/dev/null || exit 0
