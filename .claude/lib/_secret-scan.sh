#!/usr/bin/env bash
# _secret-scan.sh — SHARED secret-scanning library (sourced, not a hook).
# Used by commit-on-stop.sh (Stop hook) and scripts/autopilot.sh (post-PASS commit)
# so the SAME guard runs everywhere — the orchestrator commit can't bypass it.
#
# Provides: secret_scan_staged
#   Scans the current git STAGED set (git diff --cached) for secrets by BOTH
#   filename and content. Prints offending items to stdout. Returns:
#     0  = clean (no secrets staged)
#     1  = secrets found (caller MUST NOT commit/push)
#     2  = could not scan (not a git repo / git error) — treat as fail-closed
#
# This is a LIBRARY under .claude/lib/ (not a hook). Sourcing it only defines the
# functions; running it directly is a harmless no-op.

# --- filename patterns (basename or path) that are always secrets ---
# Kept in sync with .gitignore and settings.json permissions.deny.
_secret_basename_match() {
  # $1 = a staged path; returns 0 if it looks like a secret file.
  local p="$1" base="${1##*/}"
  # Allow obvious template/example files FIRST — teams track these intentionally,
  # and they must win over the .env.* secret pattern below (e.g. .env.example).
  case "$base" in
    *.example|*.sample|*.template|*.dist) return 1 ;;
  esac
  case "$p" in
    secrets/*|*/secrets/*) return 0 ;;
  esac
  case "$base" in
    *.env|.env.*|*.pem|*.key|*.p8|*.p12|*.pfx|*.jks|credentials*.json|\
    id_rsa|id_ed25519|id_ecdsa|id_dsa|*.tfstate|*.tfvars|.envrc|.netrc|.git-credentials|\
    .npmrc|*.npmrc|.pypirc)
      return 0 ;;
  esac
  return 1
}

# --- content patterns: high-confidence secret tokens in ADDED lines ---
# Tuned for low false-positives, covering fixed-PREFIX credential shapes a real project most
# often leaks: AWS keys, PEM/PGP private-key blocks, Anthropic (sk-ant-), OpenAI (sk-/sk-proj-),
# Stripe (sk_live_/rk_live_/whsec_), Google (AIza/GOCSPX-/ya29.), GitHub/GitLab/Slack/npm/
# SendGrid/Azure/Mailgun/DigitalOcean tokens, JWTs, and connection-string URLs that embed a
# user:password (requires BOTH non-empty, so bare/credless URLs do NOT trip it).
# IMPORTANT — this is a regex prefix-matcher, NOT a scanner: it CANNOT catch prefix-less secrets
# (bare-hex Twilio/Mailgun-style tokens, Django/Rails random SECRET_KEY values, generic
# `password=`/high-entropy strings). For real coverage use gitleaks/trufflehog + a pre-commit
# hook. This is a best-effort commit-time speed-bump, not a guarantee.
_SECRET_CONTENT_RE='AKIA[0-9A-Z]{16}|(aws_secret_access_key|AWS_SECRET_ACCESS_KEY)[^A-Za-z0-9]{1,8}[A-Za-z0-9/+]{40}|-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----|(^|[^A-Za-z0-9])sk-(ant|proj|svcacct|admin|None)-[A-Za-z0-9_-]{20,}|(^|[^A-Za-z0-9])sk-[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{16,}|rk_live_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{16,}|GOCSPX-[A-Za-z0-9_-]{20,}|ya29\.[A-Za-z0-9_-]{20,}|dop_v1_[a-f0-9]{40,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|glpat-[A-Za-z0-9_-]{16,}|npm_[A-Za-z0-9]{30,}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|key-[0-9a-f]{32}|ey[A-Za-z0-9_-]{8,}\.ey[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|AccountKey=[A-Za-z0-9/+]{40,}|[a-zA-Z][a-zA-Z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]:@]+@'

# _secret_content_hits <git-diff-args...>: emit up to 10 ADDED lines (leading '+'
# stripped) that contain a high-confidence secret token. Shared by both scanners so the
# content rule lives in one place. We deliberately do NOT print line numbers — the only
# honest number here would be a diff-stream offset, which is meaningless to the user.
_secret_content_hits() {
  git diff "$@" --unified=0 2>/dev/null \
    | grep -E '^\+' | grep -Ev '^\+\+\+' \
    | grep -E "$_SECRET_CONTENT_RE" 2>/dev/null \
    | head -10 | sed 's/^+//'
}

# secret_scan_staged: scan the staged index. Echoes findings; returns 0/1/2.
secret_scan_staged() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }

  local -a found=()
  local staged hits line
  # 1) filename scan
  while IFS= read -r staged; do
    [ -z "$staged" ] && continue
    _secret_basename_match "$staged" && found+=("  [filename] $staged")
  done < <(git diff --cached --name-only 2>/dev/null)

  # 2) content scan over ADDED lines only.
  hits=$(_secret_content_hits --cached)
  if [ -n "$hits" ]; then
    found+=("  [content] high-confidence secret token(s) in staged diff:")
    while IFS= read -r line; do [ -n "$line" ] && found+=("      $line"); done <<< "$hits"
  fi

  if [ "${#found[@]}" -gt 0 ]; then printf '%s\n' "${found[@]}"; return 1; fi
  return 0
}

# secret_scan_diff <git-range>: scan a commit RANGE (e.g. "$BASE..HEAD") by filename
# and content. Used before pushing (the builder's per-task commits don't pass through
# the Stop-hook guard, so this is the gate that stops a secret reaching a remote).
# Echoes findings; returns 0 clean / 1 secrets / 2 cannot-scan (fail-closed).
secret_scan_diff() {
  local range="$1"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "secret-scan: not a git repo"; return 2; }
  [ -z "$range" ] && { echo "secret-scan: no range given"; return 2; }
  # Fail CLOSED if the range can't be resolved. Otherwise `git diff` errors to empty (2>/dev/null)
  # and BOTH endpoints below yield no findings — so a forged/stale/rewritten base ref would be
  # reported "clean", silently bypassing this gate (and, in tick.sh, the high-stakes scan that
  # runs only after this one passes). Validate both endpoints as commits first.
  git rev-parse --verify --quiet "${range%%..*}^{commit}" >/dev/null 2>&1 \
    && git rev-parse --verify --quiet "${range##*..}^{commit}" >/dev/null 2>&1 \
    || { echo "secret-scan: cannot resolve range '$range' — fail-closed"; return 2; }
  local -a found=()
  local f hits line
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    _secret_basename_match "$f" && found+=("  [filename] $f")
  done < <(git diff --name-only "$range" 2>/dev/null)
  hits=$(_secret_content_hits "$range")
  if [ -n "$hits" ]; then
    found+=("  [content] secret token(s) in range $range:")
    while IFS= read -r line; do [ -n "$line" ] && found+=("      $line"); done <<< "$hits"
  fi
  if [ "${#found[@]}" -gt 0 ]; then printf '%s\n' "${found[@]}"; return 1; fi
  return 0
}

# Running directly = no-op (this file is a library, not a hook).
return 0 2>/dev/null || exit 0
