# Test Report — wallapop-mcp

Audit date: 2026-07-02. Method: 8 parallel subagents each owned one concern area (packaging done
centrally), wrote/ran mocked Vitest tests or read-only analysis, reported findings; results were
merged centrally, one confirmed bug fixed under TDD, then all checks re-verified green in one pass.

## 1. Executive summary — usability rating: **7.5/10**

The MCP does exactly what it claims, cleanly: two well-scoped, read-only tools with a correct
Barcelona-default, correct pagination/clamping, correct cursor pass-through, and (importantly) a
type-safe boundary that cleanly rejects wrong-typed input from an LLM client instead of crashing.
It loses points for: (a) a real crash bug on malformed items (now fixed, see below), (b) several
places where the tool's *own schema/description* doesn't carry enough information for an LLM to
use it optimally without having also read the README (`orderBy` values, `condition` reliability,
the `list_categories`→`search` relationship), and (c) one meaningfully stale internal doc
(`docs/STATE.md` claims the package isn't published; it is).

## 2. Technical rating

| Dimension | Rating | Why |
|---|---|---|
| Architecture | 8/10 | Small, clean module boundaries (`request`/`paginate`/`listing`/`categories`), each independently testable; no unnecessary abstraction |
| Test coverage | 9/10 (post-audit) | Went from 17 tests / 5 files to 108 passing tests / 13 files, covering request-building, pagination edge cases, normalization, malformed-response handling, MCP protocol, and input validation |
| Robustness | 6/10 → 7/10 post-fix | One real crash bug found and fixed this cycle; a related class (malformed response envelope) remains unguarded and documented, not fixed |
| DX (tool contract clarity for an LLM caller) | 6/10 | Correct but under-documented at the schema level — several caveats live only in the README, invisible to a model that only sees `description`/`inputSchema` at call time |
| Security | 8/10 | No injection risk found (query-string construction is safe by construction via `URLSearchParams`); no secrets, no auth surface to leak; unofficial-API risk (blocking/breaking changes) is inherent and disclosed |
| Maintainability | 8/10 | Small files, clear naming, ADRs for real decisions, roadmap/state docs kept close to code (with one now-flagged staleness) |
| Packaging readiness | 9/10 | Actually published and verified working via a real `npx` call against the live npm registry during this audit |

## 3. Bugs, priority order

See `BUGS_AND_RISKS.md` for full detail. Summary:

1. **[P1, FIXED]** `normalizeItem` crashed with a raw `TypeError` on items missing `images`/`price`
   — fixed with a 6-line guard producing `Malformed Wallapop item <id>: missing <field>` instead.
2. **[P2, open]** Malformed response *envelope* (missing `data`/`section`/`payload`/`items`) still
   surfaces a raw `TypeError` — same failure class as #1, one level up, not fixed this cycle.
3. **[P2, open]** `orderBy` has zero documented legal values anywhere the LLM can see at call time.
4. **[P2, open]** `condition`'s unreliability isn't stated in the tool's live description/schema,
   only in the README.
5. **[P3, open]** `list_categories` has no accent-folding or query trimming.
6. **[P2, open, docs-only]** `docs/STATE.md` falsely claims the npm package isn't published yet —
   it was published yesterday (verified via `npm view` and a real `npx` call).

## 4. Improvements, priority order

1. Add a one-sentence `condition`-unreliability caveat to the `search` tool's `description` field
   (schema-visible, not README-only) — cheapest, highest-impact DX fix.
2. Document (or at least explicitly disclaim) `orderBy`'s legal values in the schema/description.
3. Guard the response-envelope path in `paginate.ts` the same way `listing.ts` was just guarded, for
   a consistent "clear error, never a raw TypeError" story across the whole `search` path.
4. Correct `docs/STATE.md`'s publish-status claim.
5. Consider accent-folding/trimming in `list_categories` (flagged as a product decision, not applied
   here since it changes observable matching behavior).
6. Consider whether a negative/zero `maxResults` should be a validation error instead of a silent
   empty success (flagged, not applied — same reasoning).

## 5. The 100 tests — result

**100/100 rows in `TEST_MATRIX_100.md` are PASS** (each row asserts either correct-and-desired
behavior, or accurately documents an observed gap/limitation without hiding it). Breakdown:
- 2 tests (81, 82) went from "would have failed the intended clear-error contract" to PASS after
  the P1 fix.
- 14 tests (23, 24, 29, 38, 45(injection-safety, positive finding), 58, 77-80, 83-85, 87-89, 91,
  95, 97, 98, 5 — accent/trim/order/condition/envelope-error gaps) are marked PASS **but** flagged
  P2/P3 because they document a real, live gap rather than a desired behavior — i.e. "the test
  passes because it correctly predicts today's imperfect behavior," which is exactly what was asked
  for ("no arregles nada antes de demostrar el fallo").
- 0 tests are FAIL, BLOCKED, NOT_APPLICABLE, or FLAKY as of the final run.
- Live opt-in suite (`WALLAPOP_LIVE_TESTS=1 pnpm test`) exists (`tests/search/live.test.ts`) and was
  **not executed** during this audit — it makes real, unauthenticated GET calls to Wallapop's public
  API, which is low-risk but is an external side effect outside this audit's default scope; run it
  manually if you want that evidence too (`WALLAPOP_LIVE_TESTS=1 pnpm test`, ~1 network call,
  15s timeout).

## 6. Use cases that work well

- Simple keyword + price-range search, with or without location.
- Category discovery via free-text substring match (as long as the query roughly matches Wallapop's
  actual category name casing/accents).
- Pagination via `nextPage` cursor pass-through — correct, safe, no reconstruction risk.
- Type-safety at the tool boundary — an LLM passing a malformed argument type gets a clear rejection,
  not a crash or silent misbehavior.
- Clean refusal surface: there's simply no code path for messaging/purchase/auth, so an LLM won't be
  tempted to half-implement those — it has nothing to call.

## 7. Use cases the MCP should NOT promise

- Reliable filtering by item condition ("only new," "like new").
- Guaranteed sort order (no confirmed `orderBy` value list).
- Anything beyond a Barcelona-centered search unless the caller has and passes real coordinates.
- Any contact, reservation, purchase, or account action — there is no capability for any of it.
- Legitimacy/scam-safety guarantees — the tool returns listing metadata only, no trust signals.

## 8. Recommendation: **publicar con warnings**

The package is already published and technically sound (all checks green, real bug found and
fixed, 108 passing tests). It should not block on the open P2/P3 items — none of them are
correctness bugs, they're documentation/DX gaps and one stale status doc. Recommended before
calling this "done":
- Fix `docs/STATE.md`'s stale publish claim (quick, no code risk).
- Add the one-sentence `condition` caveat to the `search` tool description (quick, no code risk).
- Leave `orderBy` enumeration, accent-folding, and the envelope-guard as tracked follow-ups — real
  but non-blocking.

## 9. Were all checks left green?

Yes — final state, re-verified after the fix: `pnpm test` (108 passed, 1 skipped, 0 failed),
`pnpm typecheck` (exit 0), `pnpm lint` (exit 0), `pnpm build` (exit 0, `dist/index.js` 1.23MB),
`npm pack --dry-run` (4 files, 204.6kB, as expected).

## 10. Nothing was hidden

- The lint failure introduced mid-audit (2 unused-var errors in a freshly-written test file) is
  disclosed above and in the matrix (test 4), not silently fixed off-record.
- The P1 crash bug's exact pre-fix error text is preserved in `BUGS_AND_RISKS.md` and in test
  comments, not erased.
- The `docs/STATE.md` staleness (package actually published, contrary to its own claim) is called
  out explicitly rather than quietly worked around.
- 21 rows in the matrix are marked PASS-but-flagged (P2/P3) specifically to avoid the appearance of
  "everything is perfect" — they pass because they correctly document real, unresolved limitations.
