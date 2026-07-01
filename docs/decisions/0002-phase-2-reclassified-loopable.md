# ADR-002: Reclassify Phase 2 (category codegen) from supervised to loopable

Date: 2026-07-01
Decision: Changed `docs/ROADMAP.md` Phase 2's `Mode:` from `supervised` to `loopable`, at the
user's explicit direction, allowing `/autopilot` to build and auto-tick it.
Why: The phase's only external effect is a one-off read-only GET to Wallapop's public
`api/v3/categories` endpoint — unauthenticated, no money/auth/delete/prod-mutation involved, and
the output (a generated static file) is fully reversible by re-running the script or reverting
the commit. The default `supervised` tag (rejected as the prior default) over-applied the
"external side effect" caution from `.claude/rules/high-stakes.md`, which is aimed at
side effects with real-world consequences (payments, emails, prod data) rather than a public
read-only fetch.
