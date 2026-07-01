# Roadmap

> Each phase must leave the app in a working, demoable state.
> `- [ ]` = todo, `- [x]` = done. The /phase command and hooks read these.
> `Mode: supervised` is enforced by scripts/tick.sh at completion time: it refuses
> auto-tick and stops for human review. Use `loopable` only for low-risk, verifiable phases.

## Phase 1 — Project scaffold & MCP server skeleton
- [ ] pnpm-managed TypeScript/ESM project (package.json, tsconfig, tsup build config, vitest config)
- [ ] ESLint + Prettier configured, wired to `pnpm lint` / `pnpm format`; `pnpm typecheck` runs `tsc --noEmit`
- [ ] Minimal MCP server over stdio transport that responds to `tools/list` with an empty/placeholder tool set
- [ ] `pnpm build` produces a runnable single-file bundle; a smoke test starts the server and lists tools
Done when: `pnpm build && pnpm test && pnpm typecheck && pnpm lint` pass, and a manual `tools/list` call against the built stdio server returns a response (no tools required yet).
Mode: loopable

## Phase 2 — Category tree codegen & `list_categories` tool
- [ ] One-off codegen script that fetches `api/v3/categories` and flattens it into a static generated TS module (per `docs/adr/0001-static-generated-category-tree.md`), checked into the repo
- [ ] `list_categories` tool: free-text search over the static tree; returns top-level categories when no query is given
- [ ] Vitest unit tests for the flatten/search logic against a fixture category tree (no live network call in tests)
Done when: `pnpm test` passes for category flatten/search logic, and calling `list_categories` with no query returns exactly the top-level categories from the generated static file.
Mode: supervised
<!-- supervised: the codegen script makes a live call to Wallapop's unofficial API — an external side effect outside our control -->

## Phase 3 — `search` tool: request building
- [ ] Map full `api/v3/search` parameter surface (keywords, category_id, min/max price, distance_in_km, order_by, etc.) to an outgoing request
- [ ] Default location fallback to Barcelona-center lat/long when caller omits coordinates
- [ ] Hardcoded, non-configurable request headers (User-Agent, X-DeviceOS)
- [ ] Mocked-HTTP Vitest unit tests asserting constructed request params/headers for representative inputs
Done when: `pnpm test` passes for request-building unit tests, covering at least one case with full params and one with only `keywords` (verifying the Barcelona-center default).
Mode: loopable

## Phase 4 — `search` tool: response normalization
- [ ] Map raw `api/v3/search` response items to the trimmed `Listing` shape (id, title, description, price, currency, one image_url, constructed item url, location, condition, created_at)
- [ ] Explicitly exclude Wallapop-internal presentation fields (bump, favorited, is_top_profile, taxonomy)
- [ ] Mocked-HTTP Vitest unit tests asserting normalized `Listing` objects match the spec shape exactly, using a fixture raw response
Done when: `pnpm test` passes for normalization unit tests, and a fixture raw response with internal fields present produces `Listing` objects with none of those fields.
Mode: loopable

## Phase 5 — `search` tool: pagination & result clamping
- [ ] Auto-pagination loop driven by `max_results` (default 40, cap 200), passing the opaque `next_page` cursor through untouched (never decoded/reconstructed)
- [ ] Wire request building (Phase 3) + normalization (Phase 4) + pagination into the end-to-end `search` MCP tool
- [ ] Mocked-HTTP Vitest unit tests asserting the pagination loop stops at `max_results`/the 200 cap and cursor pass-through is untouched
Done when: `pnpm test` passes for pagination unit tests, and an end-to-end mocked `search` tool call with `keywords: "iphone"` and no location returns a non-empty list of `Listing`s within the requested `max_results` bound (satisfies the spec's success criterion under mocked HTTP).
Mode: loopable

## Phase 6 — Error surfacing & opt-in live integration tests
- [ ] Upstream HTTP failures surface immediately as MCP tool errors — no retry/backoff logic anywhere in the request path
- [ ] Vitest unit tests asserting a mocked upstream failure (e.g. non-2xx, network error) becomes a tool error, not a thrown/uncaught exception or a silent empty result
- [ ] Opt-in live integration test suite (real Wallapop API calls) gated behind an env var, excluded from the default `pnpm test` run
Done when: `pnpm test` (default, mocked-only) passes including the upstream-failure-to-tool-error cases, and running the live suite with the env var set against the real API returns a non-empty `search` result (run manually, not part of CI).
Mode: supervised
<!-- supervised: exercises live calls to an unofficial third-party API — external side effect, possible blocking/rate-limit risk -->

## Phase 7 — Publish packaging
- [ ] `bin` entry wiring the built stdio server as an executable CLI (`wallapop-mcp`)
- [ ] MIT license file
- [ ] README with setup instructions and an explicit unofficial/unaffiliated-with-Wallapop disclaimer
- [ ] `package.json` metadata correct for npm publish (name, version, files, bin)
Done when: `npm pack --dry-run` succeeds and includes the built bundle + bin entry, and the README contains the unofficial/unaffiliated disclaimer.
Mode: loopable
