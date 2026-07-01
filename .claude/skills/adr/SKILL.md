---
name: adr
description: Records an architectural decision as a terse 4-line ADR in docs/decisions/. Use when a real choice is made between alternatives (a library, a pattern, a data model, an algorithm) — anything a future reader would otherwise have to reverse-engineer. Triggers: "log this decision", "write an ADR", "we decided to...", "record why we chose".
---

# ADR capture

When the user has made a genuine architectural decision, record it. Do NOT use
this for trivial or reversible choices (variable names, formatting) — only for
decisions where someone later would ask "why was it done this way?"

## Steps
1. Get the next ADR number deterministically: `NNN=$(bash scripts/next-adr.sh)` (it returns the
   next zero-padded number, e.g. `004`, and errors on a collision). Fall back to "highest existing
   ADR-NNN + 1, or 001 if empty" only if the script is unavailable.
2. Write a new file `docs/decisions/ADR-<NNN>-<kebab-title>.md` with EXACTLY this shape:

   ```
   # ADR-<NNN>: <short title>

   Date: <YYYY-MM-DD>
   Decision: <what was chosen, one sentence>
   Why: <the reason AND the main alternative rejected, one or two sentences>
   ```

3. Keep it to those four lines. No "Status", no "Consequences" section, no padding.
   The value is that it's short enough to actually get written.
4. Confirm to the user: "Logged ADR-<NNN>: <title>."

## Guardrails
- One decision per ADR. If the user describes several, write several files.
- If the "decision" is actually still under discussion, say so and don't write it —
  ADRs record decisions already made, not options being weighed.
- Pull the date from the system; never guess it.
