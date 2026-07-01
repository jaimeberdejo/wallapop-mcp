---
name: scope-guard
description: Checks that a change matches its stated task and nothing more. Use before committing or when reviewing what was just built — "did I stay on scope", "check this didn't touch anything it shouldn't", "review before commit". Catches helpful-over-reach: unrelated edits, drive-by refactors, unexpected deletions.
disallowed-tools: Edit, Write, MultiEdit, NotebookEdit
---

# Scope guard

The most common failure in agent-assisted work is doing MORE than asked —
refactoring nearby code, "improving" unrelated files, deleting things that
looked unused. This skill catches that before it lands.

## Steps
1. **State the task in one line.** Pull it from the user, the active plan, or
   docs/STATE.md. If the intended scope is unclear, ask before judging.
2. **Read the diff** (`git diff` and `git diff --cached`, plus `git status` for
   new/deleted files).
3. **Classify every changed file** into:
   - **In scope** — directly required by the task.
   - **Justified support** — needed to make the in-scope change work (a new import, a test).
   - **Out of scope** — unrelated edits, opportunistic refactors, formatting churn in
     untouched files, deletions not implied by the task.
4. **Flag the out-of-scope items explicitly**, with file and a one-line reason.
   Pay special attention to: deleted files/functions, changes in directories the
   task never mentioned, and renames that ripple wider than needed.

## Verdict
- `IN SCOPE` — everything maps to the task or directly supports it.
- `SCOPE CREEP: <items>` — list each out-of-scope change and recommend whether to
  revert it, split it into its own commit, or keep it (with the user's say-so).

## Guardrails
- Don't revert anything yourself — surface it and let the user decide.
- "It's an improvement" is not the same as "it's in scope." Note good ideas as
  candidates for a separate, deliberate change.
