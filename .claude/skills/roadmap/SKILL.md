---
name: roadmap
description: Turns a spec into docs/ROADMAP.md — an ordered set of phases, each with a checklist and a measurable "Done when:" line, and each marked loopable or supervised. Use after a spec exists and before building — "write the roadmap", "break this into phases", "plan the milestones", "turn the spec into a roadmap". Produces the work queue the /phase and autopilot loops read.
---

# Roadmap

The roadmap is the work queue every loop in this stack reads. A good one makes
autonomy safe; a vague one makes it dangerous. This skill turns docs/SPEC.md into
phases that are each verifiable, bounded, and demoable.

## Before writing

1. Read `docs/SPEC.md` (and `docs/STATE.md` if present). If there is no SPEC or no
   **measurable** success criterion in it, STOP and say so — a roadmap without a
   measurable target produces unverifiable phases. Offer to grill the spec first.
2. Note the constraints (stack, data sources, compliance, performance budgets) — they
   shape phase boundaries.

## Decide how many phases (don't hardcode a number)

Phase count should fit the project, not a template. First estimate the natural number
from the spec's scope, then recommend a granularity and let the user choose:

1. **Estimate** the natural count from scope: count the distinct vertical slices the spec
   implies (data model, each interface, eval harness, hardening, each integration…).
2. **Recommend a tier**, with a one-line reason:
   - **Few / coarse (~3–4 phases):** large chunks. Fastest setup, least overhead. Best for
     small or throwaway projects you'll supervise closely. Trade-off: bigger phases are
     harder to verify atomically and riskier to autopilot.
   - **Medium (~5–7 phases):** balanced. The default recommendation for most projects.
   - **Many / fine (~8–12+ phases):** small vertical slices. Best for autonomy (smaller =
     safer to loop), high-stakes code, and ownership/learning (teach-back per small phase).
     Trade-off: more ceremony.
3. **Ask the user** which they want — "Few, Medium, or Many phases? (or give me a number)" —
   and **state your recommendation up front** with the reason (e.g. "I'd recommend Medium,
   ~6 phases: the spec has one data model, two interfaces, an eval harness, and a hardening
   pass — that splits cleanly into 6"). If the user gives an explicit number, use it. If
   they don't answer, default to your recommendation.

Then produce that many phases, ordered so each one builds on the last. Every phase MUST:

- **Leave the app in a working, demoable state.** No phase ends with a half-wired feature.
- **Be one vertical slice / bounded scope.** If a phase would touch ~30 files, split it.
- Have a **checklist of concrete tasks** (`- [ ]`), each small enough to TDD.
- End with a **`Done when:` line that names an observable, machine-checkable condition** —
  a passing command, an eval threshold, a curl that returns the right thing.
  Good: "pytest passes AND the eval test asserts ≥15/20 within ±20%."
  Bad: "the pricing feels reasonable."

Order heuristic: pure logic / data model first → evaluation harness early (it's the
truth source) → interfaces → hardening last.

## Mark each phase loopable or supervised

After each phase, add one line: **`Mode:`** `loopable` or `supervised`.
A phase is **loopable** only if it has ALL four: a machine-checkable done condition,
bounded scope, independent verifiability (the evaluator can confirm from diff + a
command), and a low/reversible blast radius. If it fails any — especially anything
touching money, auth, prod migrations, or compliance judgment — mark it **supervised**.

> **The `Mode:` tag is ENFORCED.** `scripts/tick.sh` parses the phase's `Mode:` line, and a
> phase marked `supervised` REFUSES to auto-tick (it exits "supervised", same as a high-stakes
> hit) in every mode — headless and in-session. It is backed up by the high-stakes **path** and
> **content** gates (`.claude/lib/_high-stakes.sh`), matched against the phase diff. Still keep
> genuinely sensitive work under a sensibly-named path, but a `supervised` tag alone now blocks
> the auto-tick.

## Output format (write to docs/ROADMAP.md)

```md
# Roadmap

> Each phase must leave the app in a working, demoable state.
> `- [ ]` = todo, `- [x]` = done. The /phase command and hooks read these.

## Phase 1 — <goal>
- [ ] <task>
- [ ] <task>
Done when: <observable, checkable condition>
Mode: loopable | supervised

## Phase 2 — <goal>
...
```

## After writing

- Tell the user how many phases, and which are `supervised` (and why).
- Update `docs/STATE.md` "Next action" to point at the first phase.
- Do NOT start building. The roadmap is a plan; building is `/phase` or `/autopilot`.

## Guardrails
- Phases come from the spec, not from imagination — every phase should trace to an
  in-scope item. Flag anything you're adding that the spec doesn't cover.
- Keep "Done when:" measurable. If you can't make it measurable, the phase is too vague
  to automate — say so and propose how to make it checkable.
- One milestone's worth of phases. Don't roadmap the entire product; roadmap the next
  shippable increment.
