# Lean Stack — the scaffold (SCAFFOLD.md)

> This file ships **with the scaffold** into your project. It is named `SCAFFOLD.md`
> (not `README.md`) on purpose, so it can never clobber or be mistaken for your own
> project's README. Delete it once you've read it — your repo's README is yours.

This is the self-contained quick-start for the lean Claude Code setup that was
installed into this repo. The full toolkit README is **not** copied into your
project (so it doesn't pollute it); read it on GitHub:

- <https://github.com/jaimeberdejo/my-claude-code-setup>

## What got installed here
- **CLAUDE.md** — lean constitution (edit the `<...>` placeholders). Includes the Ownership section.
- **.claude/** — hooks, commands (`/phase` `/autopilot` `/wrap` `/resume`), the `evaluator` subagent,
  and the shared guard libs (`_secret-scan.sh`, `_high-stakes.sh`).
- **.claude/skills/** — the workflow + ownership skills (roadmap, adr, ship-check, scope-guard,
  explain-diff, unstick, teach-back, mapme, quizme).
- **docs/** — SPEC/ROADMAP/STATE/ARCHITECTURE templates + `decisions/` for ADRs.
- **scripts/** — `autopilot.sh` (guarded autonomous loop), `tick.sh` (the completion gate), `doctor.sh`, `test-hooks.sh`.

CI is **opt-in**: re-run the installer with `--with-ci` to also drop a
`.github/workflows/lean-stack-ci.yml` into your project.

## Quick start
The two required steps are `chmod` then `doctor.sh`:

    chmod +x .claude/hooks/*.sh scripts/*.sh
    # NOTE: don't blanket-set CLAUDE_CODE_SUBAGENT_MODEL=haiku — it OVERRIDES the
    # evaluator's sonnet frontmatter and downgrades your grader. See the README setup notes.
    # ENABLE_TOOL_SEARCH is unverified against current docs — confirm before relying on it.
    bash scripts/doctor.sh        # verify tooling, scaffold, settings, hooks
    bash scripts/test-hooks.sh    # smoke-test the hooks

Then fill in CLAUDE.md, describe the project → `docs/SPEC.md`, and run the `roadmap`
skill → `docs/ROADMAP.md`.

### Optional companions (not required)
Handy extras, not part of setup — skip them and the stack still works:

    npx skills@latest add mattpocock/skills          # grill-me / diagnose etc. — handy, not required
    npm i -g @fission-ai/openspec && openspec init    # spec-of-record lifecycle, if you want it

## Safety note
`.claude/settings.json` ships with `permissions.deny` rules so Claude can't read
`.env`/secrets/keys (`.gitignore` alone does NOT prevent reads). Extend them per project.
The autopilot loop has preflight checks, STRICT evaluator-verdict parsing, a high-stakes
gate, a shared secret-scan before any commit/push, and a per-phase thrash cap — run
`doctor.sh` green before any unattended run. Note these are a deterministic best-effort
layer, **not** an OS sandbox; for truly unattended runs use a no-creds/sandboxed
environment (see the README's "Enforcement reality" section).
