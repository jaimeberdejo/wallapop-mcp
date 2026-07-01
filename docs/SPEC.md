# Spec: wallapop-mcp

## What & why
An MCP server that wraps Wallapop's public, unofficial `api/v3/search` endpoint (plus its incidental `api/v3/categories` endpoint), exposing product search over Wallapop's marketplace as MCP tools an LLM client (e.g. Claude Desktop/Code) can call directly.

## Success criterion (measurable)
Given a `search` tool call with `keywords: "iphone"` and no location, the server returns a non-empty list of trimmed `Listing` objects (id, title, price, currency, image_url, url, location, condition, created_at) for items near the default Barcelona-center location, within the `max_results` bound requested.

## In scope
- `search` tool: full parameter surface of `api/v3/search` (keywords, category_id, min/max price, distance_in_km, order_by, etc.), with default location fallback to Barcelona center, `next_page` cursor pass-through, and `max_results` (default 40, cap 200) auto-pagination.
- `list_categories` tool: free-text search over a statically generated, full flattening of Wallapop's category tree; returns top-level categories when no query is given.
- Trimmed/normalized `Listing` response shape (see `SCOPE.md`).
- stdio MCP transport only.
- Hardcoded request headers (User-Agent, X-DeviceOS) — not configurable.
- No retry/backoff logic; upstream failures surface immediately as MCP tool errors.
- Mocked-HTTP unit tests (Vitest) for parameter building, response normalization, and pagination/clamping; opt-in live integration tests behind an env var.
- npm-publish-ready package (`wallapop-mcp`, `bin` entry, MIT license, README disclaimer of unofficial/unaffiliated status).

## Non-goals (explicitly NOT building)
- Any Wallapop endpoint other than search and categories (no item detail, user profiles, messaging, listing creation, etc.).
- Authentication/login flows — this only uses Wallapop's unauthenticated public search surface.
- HTTP/SSE transport.
- Retry/backoff or rate-limit handling.
- A curated/maintained category enum beyond the auto-generated static tree.
- Runtime-configurable request headers.

## Constraints
- Language/runtime: TypeScript, ESM, Node.
- Package manager: pnpm. Build: tsup (single-file `dist` bundle). Tests: Vitest.
- The upstream API is undocumented and reverse-engineered; it may change or block traffic without notice — this project has no control over or SLA with Wallapop.
- Category tree is generated once via a codegen script and checked into the repo (see `docs/adr/0001-static-generated-category-tree.md`); it is not fetched live at runtime.
