# MCP Usage Guide — wallapop-mcp (for an LLM client)

This describes how an LLM client (e.g. Claude) should actually use the two tools this server
exposes, based on the *real* current contract (schemas in `src/server.ts`, verified behavior in
`TEST_MATRIX_100.md`) — not aspirational behavior.

## The two tools, in one paragraph each

**`search`** — searches Wallapop's live marketplace. All 10 parameters are optional. No location →
defaults to Barcelona center (confirmed: this is stated in the tool's own `description`, not just
the README, so it's safe to rely on even without reading external docs). No `maxResults` → 40,
capped at 200 regardless of what's requested. Returns `{ listings: Listing[], nextPage?: string }`.
Upstream failures (bad HTTP status, network error) surface as a normal MCP tool error
(`isError: true`) with a readable message like `Wallapop search request failed: HTTP 429` — treat
that as "the search failed, optionally tell the user why," never retry automatically (the server
has no retry/backoff by design, per `docs/SPEC.md`).

**`list_categories`** — free-text, case-insensitive substring search over a static snapshot of
Wallapop's category tree (997 entries). No query → top-level categories only. Use it to resolve a
category name to a `categoryId` before calling `search` with that id.

## Confirmed-safe behaviors (rely on these)

- Passing the wrong JSON type (e.g. a stringified number) is safely rejected by the tool's own
  schema with a clear validation error — it will never silently misbehave or crash the server.
- `nextPage` is a fully opaque cursor: pass back exactly what a previous `search` response returned
  in `nextPage`, never modify or construct one.
- `0`/negative coordinates are treated as real values, not "missing" — only *omitting*
  `latitude`/`longitude` triggers the Barcelona default.
- Search keywords can safely contain any Unicode, symbols, or even `&`/`=` characters — there is no
  query-injection risk.

## Known contract gaps (compensate for these in how you respond, don't assume the tool covers them)

1. **`condition` is usually absent.** `search` results include a `condition` field but it's
   `undefined` on almost every real item — Wallapop's search endpoint doesn't reliably expose it.
   If a user asks for "only new/like-new items," do the search, then explicitly tell the user you
   can't reliably filter by condition (don't pretend `keywords: "nuevo"` is an equivalent filter).
2. **`orderBy` has no documented legal values.** There is no enum, no schema-level hint, nothing in
   the tool description — only a single example (`"price_low_to_high"`) in the README, which you
   may not have read. If a user asks to sort by price, you can try `orderBy: "price_low_to_high"` /
   `"price_high_to_low"`, but say you're not certain it's honored, and check whether the returned
   `listings` actually look sorted before claiming success.
3. **`list_categories` ↔ `search` is a two-step workflow, but the tools don't say so to each
   other.** If a user names a category loosely ("tecnología", "electronics"), call
   `list_categories({query: ...})` first to resolve a `categoryId`, then pass that into `search`.
   Nothing in the schema forces you to discover this — do it anyway, it's the right pattern.
4. **Category-name matching has no accent-folding or trimming.** If your first `list_categories`
   query returns `[]`, retry once with accents added/removed and without leading/trailing
   whitespace before concluding the category doesn't exist.
5. **There is no session/state on the server.** It doesn't remember your last search. If you don't
   have a `nextPage` cursor from an actual prior tool result in this conversation, don't invent one
   — run a fresh `search` instead.

## Capabilities that do NOT exist — refuse or redirect clearly

This MCP wraps exactly two read-only, unauthenticated Wallapop endpoints. There is **no**:
- messaging/contacting a seller
- favoriting/reserving an item
- viewing a single item's full detail page (only what's in the search result list)
- viewing a seller's profile
- creating/editing/deleting a listing
- logging in, authentication, or any user-specific action
- purchasing, checkout, or payment of any kind

If a user asks for any of these ("write to the seller," "reserve this," "buy it for me"), say
plainly that this tool can search Wallapop but cannot perform that action — don't imply partial
support or silently ignore the request.

## Worked examples

| User asks | What to call | What to say alongside it |
|---|---|---|
| "Find iPhone 11s under €80" | `search({keywords:"iphone 11", maxPrice:80})` | — |
| "Bikes near Barcelona" | `search({keywords:"bicicleta"})` | Results center on Barcelona (the tool's default) |
| "Cheap laptops in electronics" | `list_categories({query:"electronics"})` → `search({keywords:"laptop", categoryId:<id>})` | — |
| "Show me the next page" | `search({..., nextPage:<cursor from the prior result>})` | If no prior search exists in this conversation, ask what to search for first — don't fabricate a cursor |
| "Only show me items in like-new condition" | `search({keywords:...})` | State clearly that condition filtering isn't reliable from this tool |
| "Find something near me" (no location given) | `search({keywords:...})` (Barcelona default applies) | Say results are centered on Barcelona unless the user gives you a real location |
| "Compare prices and tell me the average" | `search({...})`, then compute the mean yourself from the returned `price`/`currency` fields | The server has no built-in statistics — this is client-side work |
| "Write to the seller" / "Buy it for me" | *(no tool call)* | Explain this MCP has no messaging or purchase capability |
| "Cheapest thing, no budget in mind" | Ask a clarifying question before calling `search` | An empty/unscoped search over all of Wallapop isn't useful |
