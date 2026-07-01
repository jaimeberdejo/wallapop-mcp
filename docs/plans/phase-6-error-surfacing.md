# Phase 6 — Error surfacing & opt-in live integration tests

## Research notes
- Read `@modelcontextprotocol/sdk`'s `McpServer.setToolRequestHandlers` (node_modules): it
  already wraps every tool handler call in a `try/catch` and converts any thrown `Error` into a
  proper `CallToolResult` with `isError: true` (`createToolError`, using `error.message` as the
  content text). So "surface immediately as an MCP tool error" needs no extra plumbing in
  `server.ts` — it just needs `searchListings`/`paginate.ts` to actually `throw` a clear `Error`
  on upstream failure, instead of silently treating a non-2xx body as valid data.
- Currently `paginate.ts` calls `fetchImpl(...).then(r => r.json())` unconditionally — a `400`
  response (`{"status":400,...}`) would parse as JSON and get treated as a real search response,
  then crash on `body.data.section.payload.items` being undefined (a confusing `TypeError`, not a
  clear error). Fixing this means checking `response.ok` before parsing.
- A network-level failure (fetch() itself rejecting, e.g. DNS/connection error) already propagates
  as a rejected promise with no extra code needed — the MCP SDK's catch handles it the same way.
- "Opt-in live integration test suite... excluded from the default `pnpm test` run" — implemented
  via `describe.skipIf(!process.env.WALLAPOP_LIVE_TESTS)`, not a separate vitest config/file
  exclusion, so `pnpm test` and the live suite are the same command; the env var just toggles
  whether the live `describe` block's tests actually run.

## Design
- `src/search/types.ts` — extend `SearchListingsOptions["fetchImpl"]`'s return type with `ok`
  and `status` (matching the real `fetch()` `Response` shape).
- `src/search/paginate.ts` — after each `fetchImpl` call, if `!response.ok`, throw
  `new Error(\`Wallapop search request failed: HTTP ${response.status}\`)` before touching the body.
- `tests/search/paginate.test.ts` (extend) — mocked non-2xx response rejects with a clear error;
  a rejecting `fetchImpl` (network error) propagates, not swallowed into an empty result.
- `tests/server.test.ts` (extend) — end-to-end mocked `search` tool call against a non-2xx
  `fetchImpl` returns `isError: true` with a meaningful message (not a stack trace, not silent).
- `tests/search/live.test.ts` — `describe.skipIf(!process.env.WALLAPOP_LIVE_TESTS)`: real
  `searchListings` call (real `fetch`, no injected mock) with `keywords: "iphone"`, asserts a
  non-empty `Listing[]`. Skipped by default; run manually with
  `WALLAPOP_LIVE_TESTS=1 pnpm test`.

## Tasks
1. Extend `fetchImpl`'s type + `paginate.ts`'s error check.
2. Unit tests for non-2xx and network-error propagation (mocked).
3. End-to-end mocked `search` tool error-surfacing test in `tests/server.test.ts`.
4. `tests/search/live.test.ts`, opt-in via `WALLAPOP_LIVE_TESTS` env var.
5. Manually run the live suite once (`WALLAPOP_LIVE_TESTS=1 pnpm test`) to confirm it passes
   against the real API — required by this phase's own `Done when:`, not just written and never
   executed.

## Done when
`pnpm test` (default, mocked-only) passes including the upstream-failure-to-tool-error cases,
and running the live suite with the env var set against the real API returns a non-empty
`search` result (run manually, not part of CI).
