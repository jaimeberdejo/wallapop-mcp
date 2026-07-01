# Phase 4 — `search` tool: response normalization

## Research notes
- Phase 3 couldn't get past a `400` on `api/v3/search`. Found the missing pieces this session:
  `filters_source` and `source` query params are required (e.g. `filters_source=quick_filters`,
  `source=search_box`); with those + `Origin`/`Referer` headers matching the real web client, the
  live endpoint returns `200` with real data. **This means `src/search/request.ts` (Phase 3) is
  missing required params** — noted below as an update to that file in this phase, and flagged in
  `docs/STATE.md` (not silently backfilling Phase 3's already-ticked "Done when:", which is about
  request-building being unit-tested, not about a live 200 — still true).
- Fetched two real live responses (iPhone and clothing searches) via Node `fetch()` (curl/wget
  denied) to pin down the actual raw item shape:
  ```
  { id, user_id, title, description, category_id, price: {amount, currency},
    images: [{ id, average_color, urls: {small, medium, big} }],
    reserved: {flag}, location: {latitude, longitude, postal_code, city, region, region2,
    country_code}, shipping: {...}, favorited: {flag}, bump: {type}, web_slug, created_at
    (epoch ms), modified_at, taxonomy: [{id, name, icon}], is_favoriteable: {flag},
    is_refurbished: {flag}, is_top_profile: {flag}, has_warranty: {flag} }
  ```
  This confirms the exact internal field names `CONTEXT.md`'s `Listing` entry already named as
  excluded (`bump`, `favorited`, `is_top_profile`, `taxonomy`) — real, not guessed.
- **Finding: no `condition` field exists anywhere in the raw item**, across both categories
  tested (18 top-level keys total, listed above, no condition/item_condition/state field).
  Modeled `Listing.condition` as optional (`string | undefined`) — read from `raw.condition` if
  Wallapop ever includes it for some category, `undefined` otherwise. The spec names `condition`
  as a `Listing` field but doesn't mandate it's always populated; fetching item detail to backfill
  it is explicitly a non-goal. Flagged as an open question.
- Item URL: `web_slug` confirmed via a real fetch to construct `https://es.wallapop.com/item/{web_slug}`
  (real `200`, same final URL — not a redirect).
- Response is nested: `data.section.payload.items` (an array), not a bare top-level array.

## Design
- `src/search/types.ts` (extend) — `RawSearchItem` (the raw shape above, only the fields we
  read) and `RawSearchResponse` (`{ data: { section: { payload: { items: RawSearchItem[] } } } }`).
- `src/search/listing.ts` — `Listing` type (id, title, description, price, currency, imageUrl,
  url, location, condition?, createdAt) and pure `normalizeItem(raw: RawSearchItem): Listing`.
- Update `src/search/request.ts` (Phase 3 file, this phase's fix): add the two now-confirmed
  required params (`filters_source`, `source`) to `buildSearchRequest`, plus `Origin`/`Referer`
  headers alongside the existing `User-Agent`/`X-DeviceOS` — still hardcoded/non-configurable,
  just a corrected/complete set. Existing Phase 3 tests get a values update, not a scope change.

## Tasks
1. `src/search/listing.ts` — `Listing` type + `normalizeItem`.
2. `src/search/request.ts` — add `filters_source`/`source` params and `Origin`/`Referer` headers.
3. `tests/search/listing.test.ts` — fixture raw item (with `bump`/`favorited`/`is_top_profile`/
   `taxonomy` present) -> asserts the normalized `Listing` has none of those keys and has exactly
   the spec's field set.
4. `tests/search/request.test.ts` (update) — full-params/keywords-only assertions extended for
   the two new params/headers.

## Done when
`pnpm test` passes for normalization unit tests, and a fixture raw response with internal fields
present produces `Listing` objects with none of those fields.
