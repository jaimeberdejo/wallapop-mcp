[![MseeP.ai Security Assessment Badge](https://mseep.net/pr/jaimeberdejo-wallapop-mcp-badge.png)](https://mseep.ai/app/jaimeberdejo-wallapop-mcp)

# wallapop-mcp

An MCP server that wraps Wallapop's public, unofficial `api/v3/search` and `api/v3/categories`
endpoints, exposing product search over Wallapop's marketplace as MCP tools an LLM client (e.g.
Claude Desktop/Code) can call directly.

> **Unofficial and unaffiliated.** This project is not affiliated with, endorsed by, or
> connected to Wallapop in any way. It talks to Wallapop's undocumented, reverse-engineered
> public API, which may change or block traffic without notice — use at your own risk.

## Install

```bash
npx wallapop-mcp
```

Or add it to your MCP client's config (e.g. Claude Desktop's `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "wallapop": {
      "command": "npx",
      "args": ["-y", "wallapop-mcp"]
    }
  }
}
```

## Tools

### `search`

Searches Wallapop's marketplace. Defaults to a Barcelona-center location when `latitude`/
`longitude` are omitted, and auto-paginates up to `maxResults` (default 40, capped at 200).

| Param | Type | Description |
| --- | --- | --- |
| `keywords` | string | Free-text search query. |
| `categoryId` | number | Restrict to a category (see `list_categories`). |
| `minPrice` / `maxPrice` | number | Price range. |
| `distanceInKm` | number | Search radius. |
| `orderBy` | string | Sort order. |
| `latitude` / `longitude` | number | Search origin; defaults to Barcelona center. |
| `nextPage` | string | Opaque pagination cursor from a previous response. |
| `maxResults` | number | Default 40, capped at 200. |

Returns `{ listings: Listing[], nextPage?: string }`, where each `Listing` has: `id`, `title`,
`description`, `price`, `currency`, `imageUrl`, `url`, `location`, `condition` (often absent —
not present on every raw item), `createdAt`.

### `list_categories`

Free-text search over Wallapop's category tree (`query`, optional). With no query, returns the
18 top-level categories.

## Use cases

Example prompts to an LLM client once `wallapop-mcp` is connected:

- **Simple search** — "Find iPhone 11s for sale on Wallapop under €80"
  → `search({ keywords: "iphone 11", maxPrice: 80 })`
- **Location-aware search** — "What secondhand bikes are listed near Barcelona right now?"
  → `search({ keywords: "bicicleta" })` (defaults to Barcelona-center when no location is given)
- **Category-scoped shopping** — "Show me what categories exist under Technology & electronics,
  then find cheap laptops in that category"
  → `list_categories({ query: "electronics" })` → `search({ keywords: "laptop", categoryId: <id> })`
- **Price-range research** — "What's the typical asking price for a PS5 on Wallapop? Show me 20
  listings sorted by price"
  → `search({ keywords: "ps5", maxResults: 20, orderBy: "price_low_to_high" })`
- **Pagination / "show me more"** — "Show me the next page of those results"
  → `search({ keywords: "ps5", nextPage: "<cursor from previous response>" })`
- **Browsing the taxonomy** — "What are Wallapop's top-level categories?"
  → `list_categories({})`

**Known limitation:** `Listing.condition` is usually `undefined` — Wallapop's search API doesn't
reliably expose item condition (see `docs/STATE.md`'s open questions) — so "find only *new*
items" isn't reliably answerable from `search` alone today.

## Development

```bash
pnpm install
pnpm test        # mocked-HTTP unit tests only
pnpm typecheck
pnpm lint
pnpm build
pnpm start        # run the built stdio server
```

Opt-in live integration tests (real calls to Wallapop's API, not part of CI):

```bash
WALLAPOP_LIVE_TESTS=1 pnpm test
```

Regenerate the static category tree (fetches Wallapop's live `api/v3/categories` once):

```bash
pnpm codegen:categories
```

## License

MIT
