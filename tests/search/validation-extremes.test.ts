import { describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../../src/server.js";
import type { RawSearchResponse } from "../../src/search/types.js";

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

describe("search MCP tool — extreme/nonsensical inputs are rejected with clear errors", () => {
  it("[83] negative minPrice is rejected as an MCP tool error, not passed through", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", minPrice: -50 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/minPrice/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[84] negative maxPrice is rejected as an MCP tool error, not passed through", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", maxPrice: -10 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/maxPrice/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[85] minPrice > maxPrice (logically inverted range) is rejected with a clear cross-field error", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", minPrice: 500, maxPrice: 10 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/minPrice/);
    expect(content[0]!.text).toMatch(/maxPrice/);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[86] distanceInKm of 0 is rejected — distance must be a positive number of km", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", distanceInKm: 0 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/distanceInKm/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[87] negative distanceInKm is rejected as an MCP tool error", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", distanceInKm: -5 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/distanceInKm/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[88] out-of-range latitude (999, valid range is -90..90) is rejected as an MCP tool error", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", latitude: 999 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/latitude/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[89] out-of-range longitude (999, valid range is -180..180) is rejected as an MCP tool error", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", longitude: 999 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text).toMatch(/longitude/i);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});

describe("search MCP tool — maxResults zero vs. negative vs. type-confused", () => {
  it("[90] maxResults: 0 returns an empty listings array and never calls fetchImpl", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", maxResults: 0 },
    });

    const content = result.content as Content;
    const parsed = JSON.parse(content[0]!.text) as { listings: unknown[] };

    expect(parsed.listings).toEqual([]);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(result.isError).toBeFalsy();
  });

  it("[91] maxResults: -20 (negative) is rejected as an MCP tool error, not a silent empty success", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", maxResults: -20 },
    });

    expect(result.isError).toBe(true);
    const content = result.content as Content;
    expect(content[0]!.text.length).toBeGreaterThan(0);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('[92] maxResults passed as a STRING ("40") instead of a number is rejected by Zod, never reaches fetchImpl', async () => {
    const items = [
      {
        id: "1",
        title: "iphone",
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
        web_slug: "slug-1",
        created_at: 1700000000000,
      },
    ];
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
      arguments: { keywords: "iphone", maxResults: "40" },
    });

    const content = result.content as Content;

    expect(result.isError).toBe(true);
    expect(content[0]!.text).toContain("MCP error -32602");
    expect(content[0]!.text).toContain("maxResults");
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('[92b] latitude passed as a STRING ("41.1") instead of a number is rejected by Zod, never reaches fetchImpl', async () => {
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
      arguments: { keywords: "iphone", latitude: "41.1" },
    });

    const content = result.content as Content;

    expect(result.isError).toBe(true);
    expect(content[0]!.text).toContain("MCP error -32602");
    expect(content[0]!.text).toContain("latitude");
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
