Close out this session:

1. Update the prose parts of docs/STATE.md: what we completed, any open questions, and the
   "## Now" / "## Next action" narrative. Do NOT edit between the `<!-- lean:auto:begin -->`
   and `<!-- lean:auto:end -->` markers — that block is machine-managed by scripts/tick.sh.

2. **Roadmap ticking is gated — you may NOT flip `- [ ]` → `- [x]` by hand.** The ONLY way to
   mark a phase done is the shared gate, scripts/tick.sh, exactly as the headless loop uses it.
   If (and only if) a phase is genuinely complete and you want to tick it:
   a. Invoke the `evaluator` subagent (Task tool) to grade the phase independently. Capture its
      full verdict. If the last line is not `PASS`, STOP — do not tick; report what's missing.
   b. Produce fresh test evidence bound to the current commit:
      `bash scripts/test-evidence.sh --allow-no-tests`
   c. Record the grade: `bash scripts/record-grade.sh "<paste the evaluator's full verdict>"`
      (it refuses unless the verdict's last line is exactly `PASS`).
   d. Run the gate: `bash scripts/tick.sh "<exact phase heading>"`. It verifies the grade +
      fresh green tests + a clean secret scan + no high-stakes changes, then ticks the roadmap
      and updates the STATE auto-block. If it REFUSES, surface the reason — do not tick by hand.
   If a phase is "built, awaiting grade," leave it unchecked and say so.

3. If any real architectural decision was made, append a 4-line ADR to a new file
   in docs/decisions/ (format: id, date, decision, why).

4. If EVERY phase in docs/ROADMAP.md is now `- [x]`, tell me the roadmap is complete and offer the
   `milestone` skill (it runs scripts/close-milestone.sh to archive + start the next batch) — but
   do NOT archive or write a new roadmap yourself unless I say so; that's a deliberate step.

Keep all of it terse. Then tell me it's safe to /clear.
