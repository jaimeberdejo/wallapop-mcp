# Phase 7 — Publish packaging

## Research notes
- No unfamiliar API/pattern here — standard npm packaging (`bin`, `files`, `LICENSE`, `README.md`).
  `tsup.config.ts` already emits a `#!/usr/bin/env node` shebang banner on `dist/index.js` (set in
  Phase 1), so the built bundle is already CLI-executable; this phase just needs to point
  `package.json`'s `bin` field at it and restrict `files` to `dist` so `npm pack` doesn't ship
  source/tests/docs.
- This phase is packaging/config, not domain logic — no TDD test is meaningful here (nothing to
  unit-test; the phase's own `Done when:` is verified by actually running `npm pack --dry-run`,
  not a Vitest assertion).
- `SCAFFOLD.md`'s own text says to delete it "once you've read it — your repo's README is yours."
  Now that a real `README.md` exists, deleting `SCAFFOLD.md` is in scope for this phase (it's the
  lean-stack installer's own instruction, not scope creep) — called out explicitly in the commit.

## Tasks
1. `package.json` — add `bin: { "wallapop-mcp": "./dist/index.js" }` and `files: ["dist"]`.
2. `LICENSE` — MIT license text.
3. `README.md` — setup/usage instructions + an explicit unofficial/unaffiliated-with-Wallapop
   disclaimer.
4. Delete `SCAFFOLD.md` per its own instructions, now that `README.md` exists.
5. Run `npm pack --dry-run` to confirm the tarball includes `dist/` (built bundle) and the `bin`
   entry, and doesn't ship `src/`/`tests/`/`docs/`.

## Done when
`npm pack --dry-run` succeeds and includes the built bundle + bin entry, and the README contains
the unofficial/unaffiliated disclaimer.
