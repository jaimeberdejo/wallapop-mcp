---
name: unstick
description: Breaks out of a circular debugging or problem-solving loop. Use when the same fix keeps failing, the user says "still broken", "we keep going in circles", "this isn't working", "I'm stuck", or when two or more attempts at the same thing have failed. Stops the thrash and resets the approach.
---

# Unstick

When attempts are repeating without progress, stop adding changes and reset.
More edits on a confused foundation just dig deeper. The fix is to step back.

## Steps
1. **Stop.** Make no new code change in this pass.
2. **Restate the actual goal** in one sentence — the observable outcome wanted,
   not the current sub-fix being attempted. Confirm this is still what matters.
3. **List what's been tried** and what each attempt actually did (not what it was
   hoped to do). Look for the pattern: are all attempts variations on one assumption?
4. **Name the assumption** that every failed attempt shares. This is usually where
   the real problem hides — the thing everyone "knows" is true that isn't being checked.
5. **Form 2–3 fresh hypotheses** that don't depend on that assumption.
6. **Recommend the single cheapest test** that would distinguish between them —
   a log line, a minimal repro, an isolated check — before writing any more fix code.

## Guardrails
- Resist the urge to propose another fix immediately; the value here is the reset.
- Prefer a diagnostic that produces evidence over a change that hopes to work.
- If the loop has burned several attempts, suggest the user also consider a clean
  context (the old context may be full of misleading dead ends).
