# Phase 3 — `search` tool: request building

## Research notes
- Tried to confirm the live `api/v3/search` contract the same way Phase 2 confirmed
  `api/v3/categories` (Node `fetch()`, not curl/wget). Unlike categories, **every** parameter
  combination tried (keywords, lat/long, no params, extra headers) returned a bare `400` with no
  message body, except: no `User-Agent`/`X-DeviceOS` → CloudFront `403` (WAF layer), and adding
  an `X-AppVersion` header → `500` (different code path, so the app layer is reachable, just
  rejecting the request for an unknown reason). Consistent with the spec's own constraint
  ("undocumented and reverse-engineered; may change or block traffic without notice") — I could
  not pin down the exact current live contract in reasonable effort.
- This does not block Phase 3: its `Done when:` only requires mocked-HTTP unit tests on the
  *constructed* request, not a successful live call — that verification is explicitly deferred to
  Phase 6's opt-in, manually-run live integration tests. Recorded as an open question in
  `docs/STATE.md` so Phase 6 knows to expect possible request-shape debugging.
- Query parameter names below are a best-effort mapping from the spec's plain-English parameter
  surface to conventional Wallapop v3 search API field names (publicly documented in various
  third-party API wrappers), since the live contract couldn't be confirmed directly. If Phase 6
  finds these wrong, fixing them is a contained change to `src/search/request.ts` only.

## Design
- `src/search/types.ts` — `SearchInput` (keywords?, categoryId?, minPrice?, maxPrice?,
  distanceInKm?, orderBy?, latitude?, longitude?, nextPage?) and `BuiltSearchRequest`
  (`{ url: URL; headers: Record<string, string> }`).
- `src/search/request.ts` — pure `buildSearchRequest(input: SearchInput): BuiltSearchRequest`:
  - Maps `keywords` -> `keywords`, `categoryId` -> `category_ids`, `minPrice` -> `min_sale_price`,
    `maxPrice` -> `max_sale_price`, `distanceInKm` -> `distance` (converted to meters),
    `orderBy` -> `order_by`, `nextPage` -> `next_page` (passed through untouched, never
    decoded/reconstructed, per the `Search Cursor` language entry).
  - `latitude`/`longitude` default to the Barcelona-center constant when omitted.
  - Headers are hardcoded and non-configurable: `User-Agent`, `X-DeviceOS`.
  - Omits query params for undefined optional fields (no empty-string params).

## Tasks
1. `src/search/types.ts` — types.
2. `src/search/barcelona.ts` — the default-location constant (named per the `Default Location`
   language entry), so it's a single, ADR-able source of truth other phases can import.
3. `src/search/request.ts` — `buildSearchRequest`.
4. `tests/search/request.test.ts` — unit tests (no network calls): full-params case asserts every
   query param + both headers; keywords-only case asserts the Barcelona-center lat/long default
   and that unset optional params are absent from the URL.

## Done when
`pnpm test` passes for request-building unit tests, covering at least one case with full params
and one with only `keywords` (verifying the Barcelona-center default).
