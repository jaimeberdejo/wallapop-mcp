# ADR-003: Reclassify Phase 6 (error surfacing & live tests) from supervised to loopable

Date: 2026-07-01
Decision: Changed `docs/ROADMAP.md` Phase 6's `Mode:` from `supervised` to `loopable`, at the
user's explicit direction, after the phase was already built and evaluator-verified (including a
real, manually-run live call against `api/v3/search`).
Why: The phase's only external effect is a read-only, unauthenticated call to the same public
Wallapop search endpoint as Phase 5 — no money/auth/delete/prod-mutation — and it's opt-in
(env-var gated, excluded from the default `pnpm test` run), same reasoning as Phase 2 (ADR-002).
Practically, `scripts/tick.sh` treats `Mode: supervised` as an unconditional refusal with no
override in any calling context (`/wrap`, `/autopilot`, headless) — leaving it supervised would
mean this phase could never be ticked through the sanctioned gate at all. The live-call risk the
tag was meant to guard against (unattended automated hits) already didn't apply: the phase was
built via manual `/phase`, not `/autopilot`, with the live suite run once under direct
supervision.
