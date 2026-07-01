# Phase 5 — `search` tool: pagination & result clamping

## Research notes
- Confirmed via the real live response fetched in Phase 4: the raw response has a top-level
  `meta.next_page` (JWT-shaped string, matches the `Search Cursor` language entry) alongside
  `data.section.payload.items`. Default live page size observed: 40 items per page.
- "Mocked-HTTP" per this phase's `Done when:` — implemented via dependency-injecting the `fetch`
  implementation into `searchListings` (a plain function param), so tests supply a stub that
  returns canned JSON per call. No real HTTP library/mocking framework needed for this project's
  scale.

## Design
- `src/search/types.ts` (extend) — `RawSearchResponse` gets `meta?: { next_page?: string }`.
- `src/search/paginate.ts` — `searchListings(input, { fetchImpl }): Promise<{ listings: Listing[]; nextPage?: string }>`:
  loops calling `buildSearchRequest` + `fetchImpl`, normalizing each page's items via
  `normalizeItem`, until `listings.length >= maxResults` (default 40, clamped to a 200 cap) or a
  page returns no `next_page`/no items. The cursor used for the next request is `data.meta.next_page`
  read straight off the previous response and passed to `buildSearchRequest`'s `nextPage` field
  untouched — never decoded/reconstructed.
- `src/server.ts` — register the `search` tool (zod input schema mirroring `SearchInput` +
  `maxResults`), calling `searchListings` with the real `fetch`.

## Tasks
1. `src/search/types.ts` — add `meta` to `RawSearchResponse`.
2. `src/search/paginate.ts` — `searchListings`.
3. `tests/search/paginate.test.ts` — mocked-fetch unit tests: (a) stops accumulating at
   `maxResults` even when more pages are available; (b) clamps a requested `maxResults` above 200
   down to 200; (c) passes the previous page's `next_page` cursor to the next request's
   `next_page` param byte-for-byte (spy on the fetched URL).
4. `src/server.ts` — register the `search` tool wired to `searchListings`.
5. `tests/server.test.ts` (extend) — end-to-end MOCKED `search` tool call (inject a stub
   `fetchImpl` reachable through the tool registration, or test `searchListings` directly with
   `keywords: "iphone"` and no location) returns a non-empty `Listing[]` within `max_results`.

## Done when
`pnpm test` passes for pagination unit tests, and an end-to-end mocked `search` tool call with
`keywords: "iphone"` and no location returns a non-empty list of `Listing`s within the requested
`max_results` bound (satisfies the spec's success criterion under mocked HTTP).
