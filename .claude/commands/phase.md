Run the next unchecked phase of docs/ROADMAP.md, autonomously:

0. If NEXT_FINDINGS.md exists, READ IT FIRST. It contains the previous evaluator's
   reasons a phase was not done. Address those findings before selecting any new
   work — do not skip past them.
1. Read docs/STATE.md and docs/ROADMAP.md. Pick the first phase with unchecked items.
2. Record the phase base (so the grader can diff the whole phase) and the phase
   heading (so the orchestrator knows which items to tick on PASS). Create .claude/
   if needed, then:
   - Determine THIS phase's exact roadmap heading line (e.g. `## Phase 2 — Eval harness`).
   - **Phase base — set it ONLY when starting a NEW phase, preserve it on a retry.**
     If `.claude/.phase-base` already exists AND `.claude/.phase-ready` contains this
     exact same heading, you are RE-RUNNING the same phase after a NEEDS_WORK — leave
     `.claude/.phase-base` untouched (it must keep pointing at the phase's true start, so
     the grader diffs the whole phase and the criteria-integrity check still sees any
     weakening). Only when there is no `.phase-base`, or `.phase-ready` names a DIFFERENT
     heading (a genuinely new phase), run `git rev-parse HEAD > .claude/.phase-base`.
   - Write the EXACT heading line to `.claude/.phase-ready`, verbatim, no extra text
     (do this in both cases — it is cheap and idempotent for the same phase).
3. **Research (only if the phase needs it).** If the phase uses an unfamiliar API, library,
   or pattern, or touches code you haven't read, do a brief research pass FIRST: read the
   relevant existing code, and consult docs (context7 / web) if available. Capture the
   findings and the chosen approach in 3–6 bullets at the top of the plan. Skip this
   entirely when the path is obvious — research is conditional, not ceremony. This is the
   R in research → plan → execute → verify.
4. Write a short plan to docs/plans/<phase-name>.md (research notes + tasks + "Done when").
5. For each task in order: write a failing test first, then minimal code to pass.
   Run the test. If green, continue. If red after 3 attempts, STOP and report the blocker.
6. When all tasks pass, invoke the `evaluator` subagent as a SELF-CHECK. If it returns
   NEEDS_WORK, address the items and re-run it (max 2 rounds). If still NEEDS_WORK, STOP
   and report — do not proceed.

DO NOT tick docs/ROADMAP.md yourself. Ticking is the orchestrator's job, gated on an
INDEPENDENT grade: under `autopilot.sh` the script ticks the phase only after a fresh
`claude --agent evaluator` process returns PASS; in manual mode you tick via `/wrap`
after you've seen the evaluator pass. The builder never marks its own work done.

When the phase is built and self-checked, update docs/STATE.md to:
"Phase <N> built, awaiting independent grade." Then STOP.

Constraints: touch src/, tests/, and docs/ freely. You MAY also touch project config and
manifests when the task genuinely needs it (package.json, pyproject.toml, lockfiles,
migrations, *.example env files) — but call out any such change explicitly. Never touch
unrelated files. Commit after each green task. Do not ask for confirmation between tasks.

HARD RULE — do not move your own goalposts. While building the current phase you MUST NOT
edit that phase's heading or its `Done when:` line in docs/ROADMAP.md, and you must not
weaken, reword, or delete any of its acceptance criteria. You are graded against that exact
standard; altering it is a false PASS. You MAY append NEW phases or add notes elsewhere in
the roadmap, but never alter the criteria you are being graded on.
