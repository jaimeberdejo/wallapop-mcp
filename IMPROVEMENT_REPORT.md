# Improvement Report — wallapop-mcp hardening cycle

Date: 2026-07-02. Follow-up to the prior 100-test audit (`TEST_REPORT.md`/`TEST_MATRIX_100.md`/
`BUGS_AND_RISKS.md`/`MCP_USAGE_GUIDE.md`), closing the 5 remaining open gaps it flagged.

## 1. Summary

This cycle applied 4 targeted, TDD'd hardening fixes to `wallapop-mcp` (a published, read-only,
2-tool MCP server wrapping Wallapop's unofficial `search`/`categories` API): defensive validation
of malformed upstream response envelopes, accent/whitespace-insensitive category matching, range
validation on nonsensical `search` inputs, and richer tool descriptions/schema text for LLM
clients. Explicitly out of scope and untouched: login, seller messaging, purchase/reservation,
favorites, item-detail scraping, seller-profile scraping, browser automation, a database, and new
transports — the server remains exactly two read-only tools. Test count: **110 passing / 1
skipped (111 total)** before this cycle → **117 passing / 1 skipped (118 total)** after, with
every check (`pnpm test`/`typecheck`/`lint`/`build`/`npm pack --dry-run`) green at the end.

## 2. Bugs fixed

### Task 1 — Malformed response envelope crash (`src/search/paginate.ts`)
- **Where**: line 46, `body.data.section.payload.items`, accessed with no guard.
- **Failure scenario**: a Wallapop response missing `data`, `data.section`, `data.section.payload`,
  or `.items` (or with `items` present but not an array) crashed with a raw, unhelpful `TypeError`.
- **Fix**: new private `extractItems(body)` function validates each level and throws a descriptive
  `Error`.
- **Before**: `Cannot read properties of undefined (reading 'section')` / `items is not iterable`.
- **After**: `Malformed Wallapop response: missing data.section` / `Malformed Wallapop response:
  data.section.payload.items is not an array` (and analogous messages for `data`/`payload`/`items`).

### Task 2 — `list_categories` accent/whitespace matching (`src/categories/search.ts`)
- **Where**: `searchCategories`'s substring match, previously plain `.toLowerCase().includes()`.
- **Failure scenario**: `"tecnologia"` (no accent) failed to match `"Tecnología"`; `"  tech  "`
  (stray whitespace) matched nothing instead of behaving like `"tech"`.
- **Fix**: new private `normalizeSearchText()` helper trims and NFD-normalizes/strips diacritics on
  both the query and each category name before comparing. Empty/whitespace-only queries still
  behave like "no query" (top-level categories only) — confirmed by a new test.
- This is purely additive: it can only make a previously-empty result set non-empty, never break a
  query that already matched something.

### Task 3 — Nonsensical `search` inputs silently accepted (`src/server.ts`)
- **Where**: the `search` tool's Zod `inputSchema` had zero range/positivity constraints.
- **Failure scenario**: `latitude: 999`, `minPrice: -50`, `distanceInKm: -5`, `maxResults: -20`, or
  an inverted `minPrice > maxPrice` range all passed straight through to Wallapop's API (or, for
  negative `maxResults`, silently produced an empty success result) with no signal to an LLM caller
  about why the search misbehaved.
- **Fix**: added `.nonnegative()`/`.positive()`/`.min()`/`.max()`/`.int()` constraints per field
  (see ADR-0004 for the exact rationale on each), plus a handler-level `minPrice <= maxPrice`
  cross-field check (a schema-level `.refine()` was considered and confirmed technically possible
  via the MCP SDK's `AnySchema` support, but rejected as a needlessly bigger structural change with
  an untested effect on the generated JSON schema — see `docs/decisions/0004-...md`).
- **Before**: `latitude: 999` → silently accepted, forwarded to Wallapop as-is.
- **After**: `latitude: 999` → `isError: true`, message names the offending field.

### Task 4 — Tool descriptions missing key caveats (`src/server.ts`)
- **Where**: `search`'s description didn't mention read-only scope, Barcelona default, maxResults
  cap, or `condition` unreliability; `orderBy`/`nextPage` had thin or missing `.describe()` text;
  `list_categories`'s description didn't mention the `categoryId` resolution workflow.
- **Fix**: rewrote both tools' `description` strings and every field's `.describe()` text to state
  these caveats directly in what an LLM client sees at call time, not just in `README.md`.
  Deliberately did **not** invent an `orderBy` enum — none is confirmed anywhere in this codebase,
  and live-API research to discover one was out of scope for this cycle.

## 3. Behavior changes

The `search` tool now **rejects** several previously-silently-accepted inputs: negative
`minPrice`/`maxPrice`, an inverted `minPrice > maxPrice` range, non-positive `distanceInKm`
(including exactly `0`, which is now invalid — only negative values were rejected before),
out-of-range `latitude`/`longitude`, and negative `maxResults`. `maxResults: 0` remains valid and
still returns an empty result with zero fetch calls (deliberately not folded into the "reject"
set — see ADR-0004 / Task 3 notes). See `docs/decisions/0004-strict-search-input-validation.md`
for the full rationale and the rejected "clamp instead of reject" alternative.

`list_categories` now matches **strictly more** queries than before (accent-folding, trimming) —
this is additive and cannot cause a previously-successful query to newly fail.

## 4. Tests added/updated

| File | Rewritten | Added | Net change |
|---|---|---|---|
| `tests/search/upstream-malformed.test.ts` | `[77]`-`[80]` (message assertion changed) | `[93]` | +1 test |
| `tests/categories/search-behavior.test.ts` | `[23]`, `[24]` (assert new folded/trimmed behavior) | `[94]` | +1 test |
| `tests/search/validation-extremes.test.ts` | `[83]`-`[91]` (assert rejection instead of pass-through); `[92]`/`[92b]` loosened to substring checks | — | 0 net (rewritten in place) |
| `tests/mcp/tool-descriptions.test.ts` | — | 8 new tests | +8 tests (new file) |

Total: 110 → 117 passing tests (net +7 across all files above; some files' internal test counts
stayed flat because existing tests were rewritten in place rather than added).

## 5. Commands run and results

```
$ pnpm install
Already up to date. Done in 494ms using pnpm v11.9.0

$ pnpm test
Test Files  14 passed | 1 skipped (15)
     Tests  117 passed | 1 skipped (118)

$ pnpm typecheck
$ tsc --noEmit
(exit 0, no output)

$ pnpm lint
$ eslint .
(exit 0, no output)

$ pnpm build
$ tsup
ESM dist/index.js 1.23 MB
ESM ⚡️ Build success in 130ms
(exit 0)

$ ls -la dist/index.js
-rwxr-xr-x@ 1 jaimeberdejosanchez staff 1288160 Jul 2 01:04 dist/index.js

$ npm pack --dry-run
📦  wallapop-mcp@0.1.1
Tarball Contents: LICENSE (1.1kB), README.md (3.7kB), dist/index.js (1.3MB), package.json (885B)
total files: 4

$ grep -rn "console\." src
(no output — zero matches, clean stdio channel)
```

A manual MCP stdio smoke check (`tools/list` against the real built `dist/index.js`) confirmed the
new `search`/`list_categories` descriptions and per-field JSON-schema constraints
(`minimum`/`maximum`/`exclusiveMinimum`) are correctly exposed to a real client.

`WALLAPOP_LIVE_TESTS=1 pnpm test` was **not** run — `tests/search/live.test.ts`'s
`describe.skipIf(!process.env.WALLAPOP_LIVE_TESTS)` gate is untouched and the env var was left
unset throughout this cycle, per the plan's constraint.

## 6. Remaining risks

- `orderBy`'s legal values are still unconfirmed — the schema now honestly says "unvalidated,
  pass-through" rather than guessing, but a caller still can't know which values Wallapop actually
  honors without a live-API research spike (explicitly out of scope here).
- `Listing.condition` still has no live-observed value across the categories tested in the original
  audit; it remains optionally-typed and now explicitly documented as unreliable rather than
  silently absent.
- `scripts/test-evidence.sh`'s pytest-first test-command-resolver heuristic (noted in
  `docs/STATE.md`'s Open Questions) is unrelated to this cycle and was left as-is.

## 7. Explicitly not implemented, and why

- No login, seller messaging, purchase/reservation, favorites, item-detail scraping, seller-profile
  scraping, browser automation, database, or new transports — all explicitly out of scope by
  instruction; the server remains exactly two read-only tools.
- No `orderBy` enum — no legal-values list is confirmed anywhere in this codebase, and confirming
  one would require live Wallapop API research, which was out of scope for this cycle (all tests
  stay mocked-HTTP by default).
- No schema-level cross-field `.refine()` for `minPrice`/`maxPrice` — technically possible via the
  MCP SDK's `AnySchema` support (confirmed by reading `node_modules/@modelcontextprotocol/sdk`'s
  type declarations), but deliberately not used: it would require restructuring `inputSchema` from
  a raw shape into an explicit `z.object(...)`, an untested change to how the JSON schema gets
  generated. The handler-level throw reuses an already-proven pattern (the existing HTTP-500-to-
  tool-error path) with zero schema-shape risk.
- No change to `src/search/request.ts` — input validation is intentionally centralized once, at the
  MCP tool boundary in `src/server.ts`, not duplicated at the lower request-building layer.
