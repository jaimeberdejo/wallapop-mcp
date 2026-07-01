# Project: wallapop-mcp

## Commands
- Test: pnpm test
- Typecheck: pnpm typecheck
- Lint/format: pnpm lint && pnpm format
- Run: pnpm start

## Working agreement
- TDD always: a failing test before implementation. No exceptions on logic code.
- One feature/phase per session. Small, single-purpose commits.
- At session start, read docs/SPEC.md, docs/ROADMAP.md, docs/STATE.md.
- Real decisions get a 4-line ADR in docs/decisions/.
- Touch src/, tests/, docs/ freely. Project config/manifests (package.json,
  pyproject.toml, lockfiles, migrations, *.example env) only when the task needs
  it, and call it out. Never touch unrelated files.
- Never edit the current phase's `Done when:` line or heading in docs/ROADMAP.md
  while building it — you must not weaken the criteria you're graded against.
- High-stakes/irreversible code (auth, migrations, money, deletes, external side
  effects): supervised only — no autopilot, smallest phases, `permission_mode: default`,
  human approval before merge. (Also in .claude/rules/high-stakes.md.)

## Docs are the source of truth (not this file, not your memory)
- docs/SPEC.md     = what we're building and why; non-goals
- docs/ROADMAP.md  = ordered phases, each with "Done when:"
- docs/STATE.md    = where we are right now + the single next action
- docs/decisions/  = ADRs (one file each)

## Autonomy
- `/phase` runs one roadmap phase end-to-end with self-verification (it does NOT tick the
  roadmap — the shared gate does that).
- **All ticking goes through `scripts/tick.sh`** — the single gate that flips `- [ ]` → `- [x]`.
  Nothing (no command, prompt, or model) may mark a phase done without passing it: it requires a
  recorded evaluator PASS, fresh green test evidence bound to the exact commit, a clean secret
  scan, and no high-stakes changes, then updates the STATE auto-block. `/wrap`, `/autopilot`, and
  `scripts/autopilot.sh` all call it.
- `/autopilot N` loops N phases IN THIS SESSION (watchable). `scripts/autopilot.sh N` loops
  headless in fresh processes (overnight). Both gate ticking through `scripts/tick.sh`. What the
  **headless script** adds is fresh-context-per-phase, evaluator-change discard, and throwaway-
  worktree isolation; the in-session loops share the tick gate but not that isolation.
- The `evaluator` subagent grades completion independently — never mark a phase
  done on the builder's say-so alone.
- `touch AGENT_STOP` halts the loop at the next tool call (it can't claw back a call already
  in flight). Write STEER.md to redirect a running loop.

## Ownership (understand what gets built)
- Before /wrap on a non-trivial phase, run `teach-back` — Claude explains it and
  quizzes you; gaps go in docs/STATE.md under "## Ownership gaps".
- Record decisions with the `adr` skill, always including the alternative rejected.
- After big changes, run the `mapme` skill to refresh docs/ARCHITECTURE.md from the code.
- Periodically (or before an interview) run `quizme` to measure understanding.
- Build high-stakes code (auth, migrations, money, deletes) in the smallest phases and be
  able to explain it line by line. See `.claude/rules/high-stakes.md`.
