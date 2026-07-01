---
name: ship-check
description: Pre-commit / pre-PR verification pass. Use before committing, opening a PR, or marking work done — when the user says "ready to commit", "ship it", "is this good to go", "before I push". Runs the project's own checks and catches the things people forget. Reports only; does not fix.
disallowed-tools: Edit, Write, MultiEdit, NotebookEdit
---

# Ship check

A final gate before code leaves your hands. Run it, report a clear PASS/FAIL,
and never wave something through that you haven't actually verified.

## Steps
1. **Run the project's checks.** Read CLAUDE.md (or README) for the real commands —
   test, typecheck, lint. Run each and capture exit status. Do not assume they pass.
   If no commands are documented, say so and ask for them rather than guessing.
2. **Scan the staged diff** (`git diff --cached`, or `git diff` if nothing staged) for:
   - Debug leftovers: console.log, print(, debugger, breakpoint(), dbg!, .only( in tests, commented-out code blocks.
   - Obvious secrets: API keys, tokens, passwords, connection strings, .env contents.
   - Stray TODO/FIXME added in this change.
   - Large accidental files (lockfiles aside): binaries, build output, node_modules, data dumps.
3. **Check the paper trail.** If logic changed, did docs/STATE.md / the task notes get updated?
   If a real decision was made, is there an ADR? Flag if missing — don't auto-write them here.
4. **Report** as a short checklist with ✓/✗ and, for any ✗, the exact file:line or command output.

## Verdict
End with one line:
- `READY` — all checks pass, nothing flagged.
- `NOT READY: <the blocking items>` — anything failed or flagged.

## Guardrails
- Don't fix things in this skill — report them. Fixing is a separate, deliberate step.
- Run the checks; never report a check as passing without having run it.
