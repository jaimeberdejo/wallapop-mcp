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

## Bugs / gaps found and NOT fixed (out of scope for a minimal cycle — flagged for a decision)

### #2 — [P2] Structural malformation of the response body still surfaces raw `TypeError`s
- **Where**: `src/search/paginate.ts` — `body.data.section.payload.items` and the `for...of items`
  loop have no guards.
- **Failure scenario**: a response missing `data`, `data.section`, `data.section.payload`, or
  `data.section.payload.items` (Wallapop changing its response shape, or a proxy/CDN returning an
  unexpected body) produces `Cannot read properties of undefined (reading 'section'/'payload'/
  'items')` or `items is not iterable` — same class of problem as #1, but at the response-envelope
  level rather than per-item.
- **Why not fixed here**: unlike #1 (a narrow, two-line guard with an obvious message), this would
  require deciding how much of the response shape to defensively validate and what error taxonomy
  to use — a slightly bigger design decision than "minimal fix," and the project's own `SPEC.md`
  frames upstream-failure handling as a deliberate, already-completed phase (Phase 6). Recommend
  scoping this as its own small phase: wrap the `data.section.payload.items` access in a single
  guard that throws `Wallapop search response missing expected shape (data.section.payload.items)`
  — mirrors the existing `HTTP <status>` error's clarity at near-zero cost.
- **Demonstrated by**: `tests/search/upstream-malformed.test.ts` tests 77-80 (all pass, all assert
  the current raw message — i.e. this is documented, not hidden).

### #3 — [P2] `orderBy` has no enumerated legal values anywhere in the contract
- **Where**: `src/server.ts` (`orderBy: z.string().optional()`, no `.describe()`) and
  `src/search/request.ts` (passed through verbatim to `order_by`).
- **Impact**: an LLM client asked to "sort by price" has to guess a string value (the only example,
  `"price_low_to_high"`, lives in the README, not in anything the model sees at tool-call time). A
  wrong guess silently no-ops or is rejected upstream with no signal distinguishing "bad sort value"
  from any other failure.
- **Recommendation**: add a `.describe()` listing known-good values once they're confirmed against
  the live API (needs a small research spike — Wallapop doesn't document its own enum), or leave it
  as free text but at least state in the description "unvalidated, passed through to Wallapop
  as-is" so the LLM knows not to trust a wrong guess. This is a documentation/DX fix, not a code fix.

### #4 — [P2] `Listing.condition`'s unreliability isn't visible at the tool-schema level
- **Where**: `src/server.ts`'s `search` tool description never mentions `condition`; the caveat only
  exists in `README.md`.
- **Impact**: an LLM client that only sees the tool's `description`/schema at call time (which is
  the common case — MCP clients don't necessarily fetch or display the README) has no way to know
  it shouldn't promise reliable "only show new items" filtering.
- **Recommendation**: append one sentence to the `search` tool's `description` string, e.g. "Item
  condition is rarely present in Wallapop's data and cannot be filtered on." Pure documentation
  change, no code/contract change.

### #5 — [P3] `list_categories` query matching has no accent-folding or trimming
- **Where**: `src/categories/search.ts` — `query.toLowerCase().includes(needle)`.
- **Impact**: `"tecnologia"` (no accent) will NOT match a Wallapop category actually named with an
  accent (e.g. `"Tecnología"`), and `"  tech  "` (stray whitespace, easy for an LLM to produce)
  returns `[]` instead of matching `"tech"`. Both are plausible LLM-generated query shapes.
- **Recommendation** (not applied — product decision, not a "bug" in the strict sense): normalize
  both sides with `.normalize("NFD").replace(/[̀-ͯ]/g, "")` and `.trim()` before
  comparing. Small, low-risk change, but changes observable search behavior, so flagging for a
  decision rather than silently changing it.

### #6 — [P2] `docs/STATE.md` is factually stale about npm publish status
- **Where**: `docs/STATE.md` — "Milestone complete... not yet published to npm — that's a
  deliberate, unautomated step."
- **Reality**: `npm view wallapop-mcp` confirms the package **is** published — `0.1.0` on
  2026-07-01T21:59:57Z and `0.1.1` on 2026-07-01T22:11:17Z, both before this audit session, by
  `jaimeberdejo <jaimeberdejo1902@gmail.com>`. A live `npx -y wallapop-mcp@0.1.1` call during this
  audit returned a correct `tools/list` response against the real registry package.
  `README.md`'s `npx wallapop-mcp` install instructions are therefore **accurate**, not aspirational
  — but the project's own state-tracking doc contradicts that. This is exactly the kind of
  "docs vs. code/reality" drift the audit was asked to check for.
- **Recommendation**: update `docs/STATE.md`'s "Next action" section to reflect that publish already
  happened; not fixed here since it's a docs-only change outside `src/**`/`tests/**` and wasn't part
  of the explicit fix authorization for this audit.

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
| 1 | P1 | **Fixed this cycle** | Crash on item missing images/price → now a clear, item-identifying error |
| 2 | P2 | Open | Malformed response envelope (`data`/`section`/`payload`/`items` missing) → raw `TypeError` |
| 3 | P2 | Open | `orderBy` has no documented legal values anywhere the LLM can see |
| 4 | P2 | Open | `condition` unreliability not surfaced in the tool schema/description itself |
| 5 | P3 | Open | No accent-folding / trimming in `list_categories` query matching |
| 6 | P2 | Open (docs-only) | `docs/STATE.md` incorrectly claims the package isn't published |
