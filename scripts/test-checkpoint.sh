#!/usr/bin/env bash
# test-checkpoint.sh — regression tests for .claude/hooks/commit-on-stop.sh (the CHECKPOINT
# Stop hook). Asserts the honesty contract: it only says "checkpointed N" when a commit truly
# happened, the count matches the files actually committed, it fails CLOSED on secrets / a
# missing scan lib, honors the loop-guard / opt-out / non-repo cases, and never hangs on stdin.
# Each case runs in an isolated mktemp repo. Run: bash lean-stack/scripts/test-checkpoint.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # lean-stack/
HOOK="$HERE/.claude/hooks/commit-on-stop.sh"
LIB="$HERE/.claude/lib/_secret-scan.sh"
GI="$HERE/.gitignore"
command -v git >/dev/null 2>&1 || { echo "test: git required"; exit 1; }
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
# Pipe-free substring test (avoids the pipefail+grep-q SIGPIPE race: grep -q closes the
# pipe on first match, the producer dies with SIGPIPE, and pipefail flags failure).
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

mkrepo(){ # $1 name; env COPYLIB=0 to omit the scan lib
  REPO="$BASE/$1"; rm -rf "$REPO"; mkdir -p "$REPO/.claude/lib"
  [ "${COPYLIB:-1}" = 1 ] && cp "$LIB" "$REPO/.claude/lib/_secret-scan.sh"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.com; git -C "$REPO" config user.name t
  [ -f "$GI" ] && cp "$GI" "$REPO/.gitignore"
  echo seed > "$REPO/seed.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
}
fire(){ OUT="$(cd "$1" || exit 1; printf '%s' "$2" | env ${FENV:-} CLAUDE_PROJECT_DIR="$1" bash "$HOOK" 2>&1)"; RC=$?; CN="$(git -C "$1" rev-list --count HEAD 2>/dev/null || echo NA)"; }
J='{"stop_hook_active":false}'

echo "checkpoint hook tests"; echo ""

mkrepo t1; echo x >> "$REPO/seed.txt"; fire "$REPO" "$J"
[ "$CN" = 2 ] && contains "$OUT" "checkpointed 1 file" && ! contains "$(git -C "$REPO" ls-files)" last-changed && ok "modified-only commits, N=1, breadcrumb not tracked" || no "modified-only" "OUT=$OUT CN=$CN"

mkrepo t2; echo new > "$REPO/n.txt"; fire "$REPO" "$J"
[ "$CN" = 2 ] && contains "$OUT" "checkpointed 1 file" && ok "untracked-only commits" || no "untracked-only" "OUT=$OUT"

mkrepo t3; echo a>"$REPO/a";echo b>"$REPO/b"; git -C "$REPO" add -A; git -C "$REPO" commit -qm f
echo m>>"$REPO/a"; rm "$REPO/b"; echo u>"$REPO/u"; fire "$REPO" "$J"
contains "$OUT" "checkpointed 3 file" && ok "mixed M+D+?? counts 3" || no "mixed" "OUT=$OUT"

mkrepo t4; fire "$REPO" "$J"
[ -z "$OUT" ] && [ "$CN" = 1 ] && [ "$RC" = 0 ] && ok "no changes: silent, no commit, no lie" || no "no-op" "OUT=$OUT CN=$CN"

mkrepo t5; echo l>"$REPO/app.log"; mkdir -p "$REPO/node_modules"; echo x>"$REPO/node_modules/x"; fire "$REPO" "$J"
[ -z "$OUT" ] && [ "$CN" = 1 ] && ok "only-gitignored: silent, no commit" || no "ignored" "OUT=$OUT"

mkrepo t6; echo x>>"$REPO/seed.txt"; fire "$REPO" '{"stop_hook_active":true}'
[ -z "$OUT" ] && [ "$CN" = 1 ] && ok "loop-guard (stop_hook_active) bails" || no "loop-guard" "OUT=$OUT CN=$CN"

mkrepo t7a; printf 'k=AKIAIOSFODNN7EXAMPLE\n'>"$REPO/c.txt"; fire "$REPO" "$J"
[ "$CN" = 1 ] && contains "$OUT" "SECRET GUARD" && ! contains "$OUT" checkpointed && [ -z "$(git -C "$REPO" diff --cached --name-only)" ] && ok "content secret: abort, index reset, no commit" || no "secret-content" "OUT=$OUT CN=$CN"

mkrepo t7c; echo o>"$REPO/s.pem"; git -C "$REPO" add -f s.pem; git -C "$REPO" commit -qm p
echo m>>"$REPO/s.pem"; fire "$REPO" "$J"
contains "$OUT" "filename] s.pem" && [ "$CN" = 2 ] && ok "tracked secret filename (.pem): abort" || no "secret-filename" "OUT=$OUT CN=$CN"

COPYLIB=0 mkrepo t8; echo x>>"$REPO/seed.txt"; fire "$REPO" "$J"
[ "$CN" = 1 ] && contains "$OUT" "missing" && ! contains "$OUT" checkpointed && ok "scan lib missing: fail-closed, no commit" || no "fail-closed" "OUT=$OUT CN=$CN"

mkrepo t9; echo x>>"$REPO/seed.txt"; FENV="LEAN_CHECKPOINT=off" fire "$REPO" "$J"
[ -z "$OUT" ] && [ "$CN" = 1 ] && ok "LEAN_CHECKPOINT=off no-op" || no "opt-out" "OUT=$OUT CN=$CN"

NG="$BASE/ng"; mkdir -p "$NG/.claude/lib"; cp "$LIB" "$NG/.claude/lib/"; echo x>"$NG/f"
OUT="$(cd "$NG" || exit 1; printf '%s' "$J" | CLAUDE_PROJECT_DIR="$NG" bash "$HOOK" 2>&1)"; RC=$?
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "not-a-git-repo: clean exit" || no "non-repo" "OUT=$OUT RC=$RC"

# honesty of count: an untracked DIRECTORY must be counted as its real files (regression for finding #1)
mkrepo t11b; mkdir -p "$REPO/pkg"; for i in 1 2 3; do echo x>"$REPO/pkg/f$i"; done; fire "$REPO" "$J"
N="$(echo "$OUT"|grep -oE 'checkpointed [0-9]+'|grep -oE '[0-9]+')"
A="$(git -C "$REPO" show --stat --format="" --name-only HEAD|grep -c .)"
[ "$N" = "$A" ] && ok "untracked-dir count matches committed files ($N=$A)" || no "untracked-dir-count" "N=$N actual=$A"

# breadcrumb: written on success, NOT left stale after a secret abort (regression for finding #2)
mkrepo t12; echo x>>"$REPO/seed.txt"; fire "$REPO" "$J"
[ "$(cat "$REPO/.claude/.last-changed" 2>/dev/null)" = "seed.txt" ] && ok "breadcrumb written on success" || no "breadcrumb-ok" "got=$(cat "$REPO/.claude/.last-changed" 2>/dev/null)"
mkrepo t12b; printf 'AKIAIOSFODNN7EXAMPLE\n'>"$REPO/x.txt"; fire "$REPO" "$J"
[ ! -s "$REPO/.claude/.last-changed" ] && ok "no stale breadcrumb after secret abort" || no "breadcrumb-abort" "stale: $(cat "$REPO/.claude/.last-changed" 2>/dev/null)"

# stdin must not hang: closed stdin and (best-effort) a pty. perl alarm stands in for timeout.
mkrepo t13; echo x>>"$REPO/seed.txt"
OUT="$(cd "$REPO" || exit 1; CLAUDE_PROJECT_DIR="$REPO" perl -e 'alarm 8; exec @ARGV' bash "$HOOK" </dev/null 2>&1)"; RC=$?
[ "$RC" != 142 ] && contains "$OUT" checkpointed && ok "closed stdin: no hang, still checkpoints" || no "stdin-closed" "RC=$RC OUT=$OUT"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] && { echo "All checkpoint tests passed."; exit 0; } || { echo "$FAIL checkpoint test(s) FAILED."; exit 1; }
