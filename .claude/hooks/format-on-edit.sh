#!/usr/bin/env bash
# PostToolUse hook (matcher: Write|Edit|MultiEdit)
# Auto-FORMATS the file Claude just touched (whitespace/style only). Deterministic,
# runs outside the context window, ~zero token cost.
#
# Deliberately format-only: it does NOT run lint --fix. Autofixers (ruff check --fix,
# eslint --fix) can change semantics silently (prune imports, drop "unused" vars) —
# the kind of invisible mutation this stack warns against. Run lint --fix yourself,
# deliberately, where you can see the diff.
#
# Best-effort: if a formatter isn't installed it is skipped silently — formatting
# should never block or error a turn.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || cd .

# Claude Code passes hook input as JSON on stdin; pull the edited file path.
# Read once; don't block on a TTY / missing pipe.
if [ -t 0 ]; then INPUT='{}'; else INPUT=$(cat 2>/dev/null || echo '{}'); fi
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
[ -z "${FILE:-}" ] && exit 0
[ ! -f "$FILE" ] && exit 0

case "$FILE" in
  *.py)
    # Format only — no `ruff check --fix` (that rewrites code, not just whitespace).
    command -v ruff >/dev/null 2>&1 && ruff format "$FILE" >/dev/null 2>&1 || true
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # Use the project-local prettier via npx; --no-install means we only run it
    # if the project actually depends on it (no surprise global mutations).
    # No `eslint --fix` — formatting only, no silent semantic rewrites.
    npx --no-install prettier --write "$FILE" >/dev/null 2>&1 || true
    ;;
esac
exit 0
