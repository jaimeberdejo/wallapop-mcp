#!/usr/bin/env bash
# PreToolUse hook — emergency stop for autonomous loops.
# `touch AGENT_STOP` in the repo root and Claude refuses all further tool calls.
# Your seatbelt for autopilot / autonomous (ralph-style) runs.

set -uo pipefail

# Resolve the repo root ROBUSTLY so the brake can't fail open just because
# CLAUDE_PROJECT_DIR is unset or a tool runs from a subdirectory: prefer the env var,
# fall back to the git toplevel, then the current dir. Check AGENT_STOP at every
# candidate — if it's present anywhere we can see, BLOCK (exit 2).
ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -z "$ROOT" ] && ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
for d in "$ROOT" "$PWD"; do
  if [ -n "$d" ] && [ -f "$d/AGENT_STOP" ]; then
    # Exit code 2 on PreToolUse blocks the tool call and feeds stderr back to Claude.
    echo "AGENT_STOP file present ($d) — halting. Remove it to resume." >&2
    exit 2
  fi
done
exit 0
