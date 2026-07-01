import { describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../src/server.js";
import { generatedCategories } from "../src/categories/generated.js";
import type { RawSearchItem, RawSearchResponse } from "../src/search/types.js";

async function connectedClient(deps?: Parameters<typeof createServer>[0]) {
  const server = createServer(deps);
  const client = new Client({ name: "test-client", version: "0.0.0" });
  const [clientTransport, serverTransport] =
    InMemoryTransport.createLinkedPair();
  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport),
  ]);
  return client;
}

function rawItem(id: string): RawSearchItem {
  return {
    id,
    title: `iPhone ${id}`,
    description: "desc",
    price: { amount: 100, currency: "EUR" },
    images: [{ id: "img", urls: { small: "s", medium: "m", big: "b" } }],
    location: {
      latitude: 41,
      longitude: 2,
      postal_code: "08001",
      city: "Barcelona",
      region: "Cataluña",
      country_code: "ES",
    },
    web_slug: `slug-${id}`,
    created_at: 1700000000000,
  };
}

describe("createServer", () => {
  it("lists the search and list_categories tools", async () => {
    const client = await connectedClient();

    const result = await client.listTools();

    expect(result.tools.map((tool) => tool.name).sort()).toEqual([
      "list_categories",
      "search",
    ]);
  });

  it("list_categories with no query returns exactly the top-level categories from the generated static file", async () => {
    const client = await connectedClient();

    const result = await client.callTool({
      name: "list_categories",
      arguments: {},
    });

    const expected = generatedCategories.filter(
      (category) => category.path.length === 0,
    );
    const content = result.content as Array<{ type: string; text: string }>;

    expect(content[0]?.type).toBe("text");
    expect(JSON.parse(content[0]!.text)).toEqual(expected);
  });

  it("search with keywords and no location returns a non-empty Listing[] within max_results (mocked HTTP)", async () => {
    const items = Array.from({ length: 40 }, (_, i) => rawItem(`${i}`));
    const body: RawSearchResponse = {
      data: { section: { payload: { items } } },
      meta: {},
    };
    const fetchImpl = vi
      .fn()
      .mockResolvedValue({ ok: true, status: 200, json: async () => body });

    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "iphone" },
    });

    const content = result.content as Array<{ type: string; text: string }>;
    const parsed = JSON.parse(content[0]!.text) as { listings: unknown[] };

    expect(parsed.listings.length).toBeGreaterThan(0);
    expect(parsed.listings.length).toBeLessThanOrEqual(40);
    expect(fetchImpl).toHaveBeenCalled();
  });

  it("surfaces an upstream search failure as an MCP tool error, not a crash or silent empty result", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 400,
      json: async () => ({ status: 400, message: "", errors: [] }),
    });

    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "iphone" },
    });

    const content = result.content as Array<{ type: string; text: string }>;

    expect(result.isError).toBe(true);
    expect(content[0]!.text).toMatch(/wallapop search request failed.*400/i);
  });
});
