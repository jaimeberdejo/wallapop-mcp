---
name: teach-back
description: After a feature is built, explains the code and then quizzes the user on it to confirm real understanding. Use after a phase/feature is built, before marking it done — "teach me what you built", "walk me through this and test me", "do I understand this". The goal is active recall, not a flattering summary.
---

# Teach-back

Code you can't explain is code you don't own. This skill closes that gap: Claude
explains what it built, then turns it around and makes the user explain it back,
surfacing exactly what they don't yet understand.

## Phase 1 — Explain (Claude → user)
Walk through the change at the level a new teammate would need. For the phase/feature
just built, cover:
1. **The moving parts** — the 3–6 pieces and how they connect (data flow, call order).
2. **The entry points** — where execution starts for this feature; what calls it.
3. **The non-obvious decisions** — anything that isn't the default choice, and why.
4. **The failure modes** — what breaks if an input is bad / a dependency is down / this is called twice.
Keep it concrete with file:line pointers. No praise, no padding.

## Phase 2 — Quiz (Claude → user, one question at a time)
Now test understanding. Ask 4–6 questions, ONE AT A TIME, waiting for the user's
answer before the next. Bias toward "why" and "what breaks if" over "what":
- "If you changed <X>, what else would you have to change?"
- "Why <this approach> instead of <the obvious alternative>?"
- "Where would a bug in <feature> most likely hide?"
- "What's the one line here you'd flag in a code review, and why?"
After each answer, say briefly whether it's right, and fill the gap if not.

## Phase 3 — Reading list
From the questions the user answered weakly or wrong, produce a short
"go understand this" list: specific files/functions to read, in priority order.
Offer to append it to docs/STATE.md under "## Ownership gaps".

## Guardrails
- One quiz question per turn — this is active recall, not a lecture.
- Grade honestly. A skill that says "correct!" to a vague answer defeats the purpose.
- If the user asks you to just summarize and skip the quiz, do it — but note that the
  quiz is where the ownership actually happens.
