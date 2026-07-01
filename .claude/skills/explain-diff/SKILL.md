---
name: explain-diff
description: Explains what a change does and where it might be wrong, as a self-review before a human looks at it. Use when the user asks "what did this change", "review my diff", "what could break here", "walk me through what you did". Focuses on risk, not praise.
disallowed-tools: Edit, Write, MultiEdit, NotebookEdit
---

# Explain diff

Turn a diff into a short, honest review. The goal is not to summarize flatteringly —
it's to surface the things a careful reviewer would catch, so the user catches them first.

## Steps
1. Read the change: `git diff` / `git diff --cached`, and the surrounding code where needed
   to understand intent (don't review lines in isolation).
2. Produce three short sections:

   **What changed** — 2–4 bullets, plain language, behavior-level not line-level.
   ("Adds retry on the upload path"; not "modified line 42".)

   **Risks & assumptions** — the important part. Call out:
   - Edge cases not handled (empty input, nulls, concurrency, failure paths).
   - Assumptions the code bakes in that might not hold.
   - Paths with no test coverage.
   - Anything that changes behavior for existing callers.

   **Worth a second look** — specific file:line pointers for the riskiest 1–3 spots.

3. If the change looks genuinely clean, say so plainly — but only after actually
   looking for problems. Don't manufacture concerns, and don't rubber-stamp.

## Guardrails
- Be specific: file:line, not "some places". Vague review is useless review.
- Review the code as written, not the intent as described — they diverge.
- No score, no grade, no praise padding. Just what changed and what to watch.
