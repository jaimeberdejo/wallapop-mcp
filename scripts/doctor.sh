#!/usr/bin/env bash
# doctor.sh — one-command health check for the lean-stack setup.
# Verifies the things autopilot.sh and the hooks silently depend on.
# Exit 0 = healthy, exit 1 = problems found.
#
# --fix applies SAFE, LOCAL, IDEMPOTENT repairs only: chmod +x hooks/scripts, create the
# docs/plans dir, create docs/FAILURES.md. It does NOT restore missing libs/hooks/scaffold
# (that needs ./install.sh --force) and never touches the high-stakes fingerprint.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 1

PROBLEMS=0
ok()    { printf '  ✓ %s\n' "$1"; }
bad()   { printf '  ✗ %s\n' "$1"; PROBLEMS=$((PROBLEMS+1)); }
warn()  { printf '  ! %s\n' "$1"; }
fixed() { printf '  ⚙ fixed: %s\n' "$1"; }

FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    -h|--help) echo "usage: doctor.sh [--fix]   (--fix applies safe, local, idempotent repairs)"; exit 0 ;;
    *) echo "doctor: unknown argument '$a' (try --fix)" >&2; exit 2 ;;
  esac
done

echo "lean-stack doctor"
[ -f .claude/.lean-stack-version ] && echo "lean-stack version: $(cat .claude/.lean-stack-version)"
echo ""

echo "Tooling:"
command -v claude  >/dev/null 2>&1 && ok "claude CLI on PATH" || bad "claude CLI not found"
command -v jq      >/dev/null 2>&1 && ok "jq installed (hooks need it)" || bad "jq not found"
command -v git     >/dev/null 2>&1 && ok "git installed" || bad "git not found"
command -v ruff    >/dev/null 2>&1 && ok "ruff available (Python format/lint)" || warn "ruff not found (Python formatting skipped)"
command -v node    >/dev/null 2>&1 && ok "node available (JS/TS tooling)"       || warn "node not found (JS/TS formatting skipped)"
echo ""

echo "Repo:"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ok "inside a git repo" || bad "not a git repo (run 'git init')"
echo ""

echo "Scaffold files:"
for f in .claude/settings.json docs/SPEC.md docs/ROADMAP.md docs/STATE.md CLAUDE.md scripts/autopilot.sh; do
  [ -f "$f" ] && ok "$f" || bad "missing $f"
done
if [ -d docs/plans ]; then ok "docs/plans/ exists"
elif [ "$FIX" -eq 1 ]; then mkdir -p docs/plans && fixed "created docs/plans/"
else warn "docs/plans/ missing (/phase writes here)"; fi
if [ -f docs/FAILURES.md ]; then ok "docs/FAILURES.md exists"
elif [ "$FIX" -eq 1 ]; then
  printf '# Failure history\n\n_Resolved evaluator findings, appended by scripts/autopilot.sh on PASS._\n' > docs/FAILURES.md \
    && fixed "created docs/FAILURES.md"
else warn "docs/FAILURES.md missing (created on the first resolved finding, or run --fix)"; fi
echo ""

echo "Agents, commands, rules:"
[ -f .claude/agents/evaluator.md ] && ok ".claude/agents/evaluator.md" || bad "missing .claude/agents/evaluator.md (independent grader)"
for c in resume wrap phase autopilot; do
  [ -f ".claude/commands/$c.md" ] && ok ".claude/commands/$c.md" || bad "missing .claude/commands/$c.md"
done
[ -f .claude/rules/high-stakes.md ] && ok ".claude/rules/high-stakes.md" || bad "missing .claude/rules/high-stakes.md"
echo ""

echo "High-stakes gate customization:"
HS_LIB=".claude/lib/_high-stakes.sh"
if [ -f "$HS_LIB" ]; then
  HS_CUR=$(grep -E '^HIGH_STAKES_RE=' "$HS_LIB" 2>/dev/null)
  if [ ! -f .claude/.high-stakes-default ]; then
    warn "cannot verify high-stakes customization — fingerprint .claude/.high-stakes-default missing"
    warn "  (re-run install.sh to create it). Confirm HIGH_STAKES_RE in $HS_LIB matches your paths."
  elif [ "$HS_CUR" = "$(cat .claude/.high-stakes-default 2>/dev/null)" ]; then
    HS_DEFAULT=1
    warn "HIGH_STAKES_RE is still the shipped default — edit it in $HS_LIB to match THIS project's"
    warn "  sensitive paths. It's the ENFORCED gate; editing only rules/high-stakes.md does nothing."
  else
    ok "HIGH_STAKES_RE customized (no longer the shipped default)"
  fi
fi
echo ""

echo "Hook files present:"
for h in session-start steer kill-switch format-on-edit test-gate commit-on-stop ownership-nudge; do
  [ -f ".claude/hooks/$h.sh" ] && ok ".claude/hooks/$h.sh" || bad "missing .claude/hooks/$h.sh"
done
echo ""
echo "Shared guard libraries (.claude/lib/):"
# Sourced by commit-on-stop.sh and autopilot.sh. If absent, the secret-scan and
# high-stakes gates silently disable, so treat as hard failures.
for lib in _secret-scan _high-stakes; do
  [ -f ".claude/lib/$lib.sh" ] && ok ".claude/lib/$lib.sh (shared guard lib)" || bad "missing .claude/lib/$lib.sh (secret/high-stakes gate disabled without it)"
done
echo ""

echo "settings.json:"
if [ -f .claude/settings.json ]; then
  jq empty .claude/settings.json >/dev/null 2>&1 && ok "valid JSON" || bad "settings.json is not valid JSON"
  jq -e '.permissions.deny | length > 0' .claude/settings.json >/dev/null 2>&1 \
    && ok "permissions.deny present (secret-read protection)" \
    || warn "no permissions.deny — Claude can read .env/secrets. Add deny rules."
  # Kill-switch wiring: the AGENT_STOP brake must be a PreToolUse hook with a match-all
  # matcher so it fires before EVERY tool call. Per the Claude Code hooks docs, "*", ""
  # and an omitted matcher all mean "match all" — accept any of them; reject a narrowed
  # matcher (e.g. "Bash") that would let other tools slip past the brake.
  if jq -e '
        [ .hooks.PreToolUse[]?
          | select([.hooks[]?.command | select(test("kill-switch"))] | length > 0)
          | (.matcher // "*") ] as $ms
        | ($ms | length > 0) and ($ms | all(. == "" or . == "*"))
      ' .claude/settings.json >/dev/null 2>&1; then
    ok "kill-switch wired into PreToolUse with a match-all matcher"
  else
    bad "kill-switch.sh not wired into PreToolUse with a match-all matcher (* / \"\" / omitted) — the AGENT_STOP brake may not fire on every tool"
  fi
fi
echo ""

echo "Hooks executable:"
# Libraries under .claude/lib/ are SOURCED, not executed — they don't need the exec bit.
for h in .claude/hooks/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  if [ -x "$h" ]; then ok "$h"
  elif [ "$FIX" -eq 1 ]; then chmod +x "$h" && fixed "chmod +x $h"
  else bad "$h not executable (run: chmod +x $h)"; fi
done
echo ""

echo "Hook shell syntax:"
for h in .claude/hooks/*.sh .claude/lib/*.sh scripts/*.sh; do
  [ -f "$h" ] || continue
  bash -n "$h" 2>/dev/null && ok "$h parses" || bad "$h has a syntax error"
done
echo ""

echo "CLAUDE.md placeholders:"
if [ -f CLAUDE.md ]; then
  # Any unresolved <...> token is a placeholder, not just the piped command form —
  # catches '<NAME>', '<pytest -q | npm test>', etc. Report the offending lines.
  PH_LINES=$(grep -nE '<[^>]+>' CLAUDE.md 2>/dev/null)
  if [ -n "$PH_LINES" ]; then
    warn "un-substituted <...> placeholder(s) in CLAUDE.md — fill them in with your real values:"
    printf '%s\n' "$PH_LINES" | sed 's/^/      /'
    UNCONFIGURED=1
  else
    ok "no <...> placeholders left in CLAUDE.md"
  fi
fi
echo ""

if [ "$PROBLEMS" -ne 0 ]; then
  echo "$PROBLEMS problem(s) found. Fix the ✗ items above before an unattended run."
  [ "$FIX" -eq 1 ] && echo "(--fix repairs chmod/dirs only — it can't restore missing libs/hooks/scaffold; run ./install.sh --force for those.)"
  exit 1
elif [ "${UNCONFIGURED:-0}" = 1 ] || [ "${HS_DEFAULT:-0}" = 1 ]; then
  # Installed correctly but not yet customized — do NOT imply it's ready to run unattended.
  echo "Installed OK, but NOT yet configured for THIS project (see the ! warnings above):"
  [ "${UNCONFIGURED:-0}" = 1 ] && echo "  • fill the CLAUDE.md command placeholders"
  [ "${HS_DEFAULT:-0}" = 1 ]  && echo "  • point HIGH_STAKES_RE in .claude/lib/_high-stakes.sh at your sensitive paths"
  echo "Finish those before an unattended autopilot run."
  exit 0
else
  echo "All good. Setup looks healthy."
  exit 0
fi
