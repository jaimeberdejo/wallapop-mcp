import { describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../../src/server.js";

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

type Content = Array<{ type: string; text: string }>;

describe("MCP protocol surface", () => {
  it("[11] connects an in-memory client and lists tools successfully", async () => {
    const client = await connectedClient();

    await expect(client.listTools()).resolves.toBeDefined();
  });

  it("[12] advertises exactly the two expected tools, no extras or typos", async () => {
    const client = await connectedClient();

    const result = await client.listTools();
    const names = result.tools.map((tool) => tool.name).sort();

    expect(names).toEqual(["list_categories", "search"]);
  });

  it("[13] search tool's input schema has exactly the expected optional properties", async () => {
    const client = await connectedClient();

    const result = await client.listTools();
    const searchTool = result.tools.find((tool) => tool.name === "search");

    expect(searchTool).toBeDefined();
    const schema = searchTool!.inputSchema as {
      properties?: Record<string, unknown>;
      required?: string[];
    };

    const expectedProps = [
      "keywords",
      "categoryId",
      "minPrice",
      "maxPrice",
      "distanceInKm",
      "orderBy",
      "latitude",
      "longitude",
      "nextPage",
      "maxResults",
    ];

    expect(Object.keys(schema.properties ?? {}).sort()).toEqual(
      [...expectedProps].sort(),
    );
    expect(schema.required ?? []).toEqual([]);
  });

  it("[14] list_categories tool's input schema has exactly one optional property: query", async () => {
    const client = await connectedClient();

    const result = await client.listTools();
    const listCategoriesTool = result.tools.find(
      (tool) => tool.name === "list_categories",
    );

    expect(listCategoriesTool).toBeDefined();
    const schema = listCategoriesTool!.inputSchema as {
      properties?: Record<string, unknown>;
      required?: string[];
    };

    expect(Object.keys(schema.properties ?? {})).toEqual(["query"]);
    expect(schema.required ?? []).toEqual([]);
  });

  it("[15] list_categories with no arguments succeeds and returns a JSON array", async () => {
    const client = await connectedClient();

    const result = await client.callTool({
      name: "list_categories",
      arguments: {},
    });

    expect(result.isError).toBeFalsy();
    const content = result.content as Content;
    expect(content[0]?.type).toBe("text");
    const parsed = JSON.parse(content[0]!.text);
    expect(Array.isArray(parsed)).toBe(true);
  });

  it("[16] list_categories with a query succeeds and returns a JSON array", async () => {
    const client = await connectedClient();

    const result = await client.callTool({
      name: "list_categories",
      arguments: { query: "tech" },
    });

    expect(result.isError).toBeFalsy();
    const content = result.content as Content;
    expect(content[0]?.type).toBe("text");
    const parsed = JSON.parse(content[0]!.text);
    expect(Array.isArray(parsed)).toBe(true);
  });

  it("[17] search with mocked fetchImpl returning no items succeeds with an empty listings array", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        data: { section: { payload: { items: [] } } },
        meta: {},
      }),
    });

    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "iphone" },
    });

    expect(result.isError).toBeFalsy();
    const content = result.content as Content;
    const parsed = JSON.parse(content[0]!.text) as {
      listings: unknown[];
      nextPage?: unknown;
    };

    expect(parsed.listings).toEqual([]);
    expect(parsed.nextPage).toBeUndefined();
  });

  it("[18] every text content block returned across calls is valid, parseable JSON", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({
        data: { section: { payload: { items: [] } } },
        meta: {},
      }),
    });

    const client = await connectedClient({ fetchImpl });

    const listCategoriesResult = await client.callTool({
      name: "list_categories",
      arguments: { query: "tech" },
    });
    const searchResult = await client.callTool({
      name: "search",
      arguments: { keywords: "iphone" },
    });

    for (const result of [listCategoriesResult, searchResult]) {
      const content = result.content as Content;
      expect(() => JSON.parse(content[0]!.text)).not.toThrow();
    }
  });

  it("[19] surfaces an upstream 500 as a readable MCP tool error", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => ({}),
    });

    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "iphone" },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    const text = content[0]!.text;

    expect(typeof text).toBe("string");
    expect(text.length).toBeGreaterThan(0);
    expect(text).not.toBe("[object Object]");
    expect(text).toMatch(/500|fail/i);
  });
});
