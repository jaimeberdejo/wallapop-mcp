---
name: quizme
description: Generates a cold-open quiz from the current codebase and grades the user's answers, to measure how well they actually understand a project Claude helped build. Use periodically or before an interview/review — "quiz me on this project", "test my understanding", "am I ready to explain this". Turns ownership into something measurable.
---

# Quiz me

Ownership is vague until you try to answer questions without help. This generates a
quiz from the real code, grades honestly, and shows the user exactly where their
understanding is thin — turning "I think I get it" into evidence.

## Steps
1. **Read enough of the codebase** to ask grounded questions — the architecture,
   the main flows, the riskiest modules. Base questions on what's actually there.
2. **Ask 6–8 questions, ONE AT A TIME**, waiting for each answer. Mix the levels:
   - *Orientation:* "Where does a <request/input> first enter the system?"
   - *Causal:* "What happens, step by step, when <core action>?"
   - *Counterfactual:* "If <dependency> were down, what would the user see?"
   - *Change-impact:* "To add <plausible feature>, which files would you touch?"
   - *Risk:* "Which part of this code is most likely to have a subtle bug, and why?"
   - *Decision:* "Why is <X> done this way rather than <alternative>?"
3. **Grade each answer honestly** right after it's given: correct / partial / off,
   with the right answer when needed. Be specific and fair — no participation trophies.
4. **Score and diagnose.** End with: a rough score, the 2–3 weakest areas, and a
   prioritized reading list (specific files/functions). Offer to save it to
   docs/STATE.md under "## Ownership gaps".

## Modes
- Default: mixed difficulty across the whole project.
- "Interview mode": harder, follow-up-heavy, phrased like a technical interviewer
  probing whether the user really built this. Useful before a real interview.
- "Focus mode": all questions on one module the user names.

## Guardrails
- One question per turn; let the user actually think.
- Don't reveal the answer inside the question. Grade after they commit to an answer.
- Grade truthfully — the entire value is an accurate picture of what they don't know.
