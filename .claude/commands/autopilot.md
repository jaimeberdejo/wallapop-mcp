Run roadmap phases autonomously IN THIS SESSION so I can watch every step. This is the
watchable in-context loop — distinct from `scripts/autopilot.sh` (headless, fresh process per
phase). Use this for a handful of phases I want to observe; use the script for long overnight runs.

**Argument = how many phases (interpret flexibly, default 3):** a number → up to that many, then
STOP; a range ("3-5") → at least the low end if context allows, at most the high end; "all"/"max"
→ until the roadmap is empty or a guardrail trips (don't burn context to hit a number).

Loop until the count target is met OR `docs/ROADMAP.md` has no `- [ ]` items:

1. **Check controls first, every iteration.** `AGENT_STOP` file → STOP and tell me. No unchecked
   items → STOP (roadmap complete). `NEXT_FINDINGS.md` exists → read and address it before anything
   else. (The steer.sh hook surfaces any `STEER.md` I write mid-run — act on it when it appears.)

2. **Build the phase: run the `/phase` procedure exactly** (research→plan→execute→verify, TDD,
   3-strike thrash cap, records `.claude/.phase-base`/`.phase-ready`). Do not restate it here.

3. **Grade + tick — ticking ONLY goes through the shared gate, never by editing checkboxes:**
   - **PASS:** produce evidence and tick with the SAME scripts the headless loop uses:
     - `bash scripts/test-evidence.sh --allow-no-tests`
     - `bash scripts/record-grade.sh "<the evaluator's full verdict text>"`
     - `bash scripts/tick.sh "<exact phase heading>"`
     `tick.sh` verifies the grade + fresh green tests + clean secret scan + no high-stakes changes,
     then flips the checkbox and updates the STATE auto-block. If it REFUSES, do NOT tick — report
     why and stop. Then commit and continue.
   - **NEEDS_WORK:** address the items, re-run the `evaluator` (max 2 rounds). If it still fails,
     write the findings to `NEXT_FINDINGS.md`, do NOT tick, and STOP — report the blocker.

4. **Between phases, manage context.** Report your running token/context budget. After 2-3 phases
   or when the window feels full, STOP and recommend I `/wrap` then `/clear` then re-run `/autopilot`
   — this in-session loop rots context the way the headless script does not.

At the end, summarize: phases completed, remaining, and the single next action. Do not push to a
remote. What this loop LACKS versus `scripts/autopilot.sh` is evaluator-change discard and throwaway-
worktree isolation — you (the watcher) are those guardrails. High-stakes work is `supervised`; for
unattended high-stakes runs there is no safe mode — do it by hand.
