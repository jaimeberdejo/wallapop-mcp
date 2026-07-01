# Bugs & Risks — wallapop-mcp

Audit date: 2026-07-02. Scope: `src/**` as of commit `1fd6fb8` plus the fix described in #1 below.

## Bugs (found and fixed this cycle)

### #1 — [P1, FIXED] `normalizeItem` crashed with a raw, unhelpful `TypeError` on malformed items
- **Where**: `src/search/listing.ts` — `raw.images[0]!.urls.big` (non-null assertion, no guard) and
  `raw.price.amount` (no guard).
- **Failure scenario**: any single item in a Wallapop search response missing `images` (empty
  array) or `price` entirely caused the whole `search` tool call to reject with
  `TypeError: Cannot read properties of undefined (reading 'urls')` or `(reading 'amount')` — a
  message that names an internal property, not the actual problem, and gives an LLM client nothing
  useful to relay to the user or to distinguish from a genuine code bug.
- **Demonstrated by**: `tests/search/listing-normalization.test.ts` (discovery tests, originally
  asserting the raw `TypeError` text) and `tests/search/upstream-malformed.test.ts` tests 81/82
  (originally asserting `.rejects.toThrow(TypeError)`).
- **Fix applied** (minimal, `src/search/listing.ts`): added two explicit guards at the top of
  `normalizeItem` that throw a descriptive `Error` — `Malformed Wallapop item <id>: missing price`
  / `missing images` — before the property access that used to crash. No change to the function's
  return shape, no change to any tool's input/output contract.
- **Tests updated to reflect new behavior**: the same two files now assert the clear,
  item-identifying message instead of the raw `TypeError`.
- **Verification**: `pnpm test` (108/108 passing), `pnpm typecheck`, `pnpm lint`, `pnpm build` all
  green after the fix.
- Real-world likelihood: **low but nonzero** — every raw item observed live during Phase 4-6
  development had both `images` and `price`, but Wallapop's API is unofficial/reverse-engineered
  and unaffiliated with this project, so a category or edge case with a missing field can't be
  ruled out. This fix is cheap insurance with zero contract cost.

## Bugs / gaps found and fixed in the follow-up hardening cycle (2026-07-02)

### #2 — [P2, FIXED] Structural malformation of the response body no longer surfaces raw `TypeError`s
- **Where**: `src/search/paginate.ts` — `body.data.section.payload.items` and the `for...of items`
  loop had no guards.
- **Failure scenario**: a response missing `data`, `data.section`, `data.section.payload`, or
  `data.section.payload.items` (Wallapop changing its response shape, or a proxy/CDN returning an
  unexpected body) produced `Cannot read properties of undefined (reading 'section'/'payload'/
  'items')` or `items is not iterable` — same class of problem as #1, but at the response-envelope
  level rather than per-item.
- **Fix applied**: a new private `extractItems(body)` function in `src/search/paginate.ts` guards
  each level of the envelope and throws `` `Malformed Wallapop response: missing <dotted.path>` ``
  (or `` `... is not an array` `` when `items` is present but not an array), mirroring `#1`'s
  per-item error-message convention.
- **Tests updated**: `tests/search/upstream-malformed.test.ts` tests `[77]`-`[80]` now assert the
  new clear message instead of a bare `TypeError`; a new test `[93]` covers `items` present but not
  an array.

### #3 — [P2, FIXED via description] `orderBy` now documents itself as unvalidated pass-through
- **Where**: `src/server.ts` (`orderBy: z.string().optional()`, no `.describe()`) and
  `src/search/request.ts` (passed through verbatim to `order_by`).
- **Fix applied**: `orderBy` now has a `.describe()` stating it's passed through to Wallapop
  unvalidated, with no enumerated list of legal values confirmed anywhere in this codebase — an
  invalid value may be ignored or rejected upstream rather than erroring in this tool. No enum was
  invented, since none is confirmed (would require a live-API research spike, out of scope).
- **Tests added**: `tests/mcp/tool-descriptions.test.ts` asserts the `orderBy` field's
  `.describe()` text mentions both "Wallapop" and "unvalidated"/"pass-through".

### #4 — [P2, FIXED] `Listing.condition`'s unreliability is now visible at the tool-schema level
- **Where**: `src/server.ts`'s `search` tool description previously never mentioned `condition`;
  the caveat only existed in `README.md`.
- **Fix applied**: the `search` tool's top-level `description` now states item condition is rarely
  present in Wallapop's raw data and should be treated as unreliable, not promised as a filter.
- **Tests added**: `tests/mcp/tool-descriptions.test.ts` asserts the `search` description mentions
  "condition".

### #5 — [P3, FIXED] `list_categories` query matching is now accent- and whitespace-insensitive
- **Where**: `src/categories/search.ts` — `query.toLowerCase().includes(needle)`.
- **Fix applied**: a new private `normalizeSearchText()` helper trims and NFD-normalizes/strips
  diacritics from both the query and each category name before comparing, so `"tecnologia"` now
  matches `"Tecnología"` and `"  tech  "` matches the same results as `"tech"`. An empty or
  whitespace-only query continues to behave like "no query" (returns top-level categories only).
- **Tests updated**: `tests/categories/search-behavior.test.ts` tests `[23]`/`[24]` now assert the
  folded/trimmed matches; a new test `[94]` locks in the whitespace-only-query decision.

### #6 — [P2, FIXED] `docs/STATE.md` no longer claims the package isn't published
- **Where**: `docs/STATE.md` — "Milestone complete... not yet published to npm — that's a
  deliberate, unautomated step."
- **Reality**: `npm view wallapop-mcp` confirms the package **is** published — `0.1.0` on
  2026-07-01T21:59:57Z and `0.1.1` on 2026-07-01T22:11:17Z, both before this audit session, by
  `jaimeberdejo <jaimeberdejo1902@gmail.com>`. A live `npx -y wallapop-mcp@0.1.1` call during the
  original audit returned a correct `tools/list` response against the real registry package.
  `README.md`'s `npx wallapop-mcp` install instructions were already accurate — only `STATE.md`
  contradicted reality.
- **Fix applied**: `docs/STATE.md`'s "Next action" section now states the package is published,
  with the confirmed version/timestamp evidence.

## Non-bugs worth recording (confirmed safe / confirmed by design)

- **Query-string injection via `keywords`** (test 45): `URLSearchParams.set` safely encodes
  arbitrary characters including `&`/`=`; a keyword value containing
  `"iphone&latitude=0&extra=1"` cannot inject or overwrite other params. No vulnerability.
- **Type confusion at the MCP boundary** (test 92): the MCP SDK validates every tool call's
  arguments against the Zod `inputSchema` *before* the handler runs. A string passed where a number
  is expected (e.g. `maxResults: "40"`) is rejected outright with a clear, structured
  `-32602 Input validation error`, not silently coerced and not a crash. This is the single most
  important safety property for an LLM client that might pass the wrong JSON type, and it holds.
- **Pagination loop termination** (test 58): there's no independent max-iteration guard, but the
  loop is unconditionally bounded by `MAX_RESULTS_CAP = 200` applied before the loop starts, so a
  buggy/adversarial upstream that always returns the same cursor with non-empty items still
  terminates within `ceil(200 / items-per-page)` fetch calls. Safe today; would need re-auditing
  if `MAX_RESULTS_CAP` were ever removed or made caller-configurable.
- **`0`/negative `latitude`/`longitude`** (test 33): correctly distinguished from "omitted" via `??`
  rather than `||` — `0` is a legitimate coordinate and is not silently replaced with the Barcelona
  default.
- **No stray stdout/stderr writes** on the executed tool-call path (test 20) — the stdio JSON-RPC
  channel is clean.
- **Category tree data integrity**: 997 flattened categories, no duplicate IDs, all required fields
  present; the one "path includes own name" case (id 10067) is a genuine Wallapop data coincidence
  (two same-named categories at different depths), not a `flattenCategories` bug.

## Priority summary

| # | Severity | Status | One-line |
|---|---|---|---|
| 1 | P1 | **Fixed** | Crash on item missing images/price → now a clear, item-identifying error |
| 2 | P2 | **Fixed** | Malformed response envelope (`data`/`section`/`payload`/`items` missing) → now a clear, path-naming error |
| 3 | P2 | **Fixed** | `orderBy` now has a `.describe()` stating it's unvalidated pass-through (no enum invented) |
| 4 | P2 | **Fixed** | `condition` unreliability now stated in the `search` tool's top-level `description` |
| 5 | P3 | **Fixed** | `list_categories` query matching is now accent- and whitespace-insensitive |
| 6 | P2 | **Fixed** | `docs/STATE.md` now correctly states the package is published |
