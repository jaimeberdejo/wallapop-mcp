import { describe, expect, it, vi } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { buildSearchRequest } from "../../src/search/request.js";
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

describe("buildSearchRequest — extreme/nonsensical inputs (no validation beyond Zod's basic type check)", () => {
  it("[83] negative minPrice is passed straight through, not rejected or clamped to 0", () => {
    const { url } = buildSearchRequest({ minPrice: -50 });

    expect(url.searchParams.get("min_sale_price")).toBe("-50");
  });

  it("[84] negative maxPrice is passed straight through, not rejected or clamped to 0", () => {
    const { url } = buildSearchRequest({ maxPrice: -10 });

    expect(url.searchParams.get("max_sale_price")).toBe("-10");
  });

  it("[85] minPrice > maxPrice (logically inverted range) is set as given, no cross-field validation/swap/error", () => {
    const { url } = buildSearchRequest({ minPrice: 500, maxPrice: 10 });

    expect(url.searchParams.get("min_sale_price")).toBe("500");
    expect(url.searchParams.get("max_sale_price")).toBe("10");
  });

  it("[86] distanceInKm of 0 sets distance=0 (not omitted, not defaulted)", () => {
    const { url } = buildSearchRequest({ distanceInKm: 0 });

    expect(url.searchParams.get("distance")).toBe("0");
  });

  it("[87] negative distanceInKm produces negative meters, nonsensical but unvalidated", () => {
    const { url } = buildSearchRequest({ distanceInKm: -5 });

    expect(url.searchParams.get("distance")).toBe("-5000");
  });

  it("[88] out-of-range latitude (999, valid range is -90..90) is set verbatim, no range check", () => {
    const { url } = buildSearchRequest({ latitude: 999 });

    expect(url.searchParams.get("latitude")).toBe("999");
  });

  it("[89] out-of-range longitude (999, valid range is -180..180) is set verbatim, no range check", () => {
    const { url } = buildSearchRequest({ longitude: 999 });

    expect(url.searchParams.get("longitude")).toBe("999");
  });
});

describe("search MCP tool — extreme/nonsensical inputs via the full in-memory client path", () => {
  it("[90] maxResults: 0 returns an empty listings array and never calls fetchImpl", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", maxResults: 0 },
    });

    const content = result.content as Array<{ type: string; text: string }>;
    const parsed = JSON.parse(content[0]!.text) as { listings: unknown[] };

    expect(parsed.listings).toEqual([]);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[91] maxResults: -20 (negative) silently returns empty listings with 0 fetch calls, NOT an MCP tool error", async () => {
    const fetchImpl = vi.fn();
    const client = await connectedClient({ fetchImpl });

    const result = await client.callTool({
      name: "search",
      arguments: { keywords: "x", maxResults: -20 },
    });

    const content = result.content as Array<{ type: string; text: string }>;
    const parsed = JSON.parse(content[0]!.text) as { listings: unknown[] };

    expect(parsed.listings).toEqual([]);
    expect(fetchImpl).not.toHaveBeenCalled();
    // Candidate product decision: a negative maxResults is nonsensical input from a
    // caller/LLM, yet it silently "succeeds" with an empty result instead of erroring.
    // This may be surprising/undesirable UX — flagging, not fixing, per task scope.
    expect(result.isError).toBeFalsy();
  });

  it('[92] maxResults passed as a STRING ("40") instead of a number — observed Zod/MCP SDK behavior', async () => {
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

    // Observed: the MCP SDK validates arguments against the Zod inputSchema
    // server-side before the tool handler ever runs, and REJECTS a string where
    // `z.number()` is declared — no coercion happens. callTool() resolves normally
    // (it does not throw) with result.isError === true and a text content block
    // whose exact text is:
    //   MCP error -32602: Input validation error: Invalid arguments for tool search: [
    //     {
    //       "expected": "number",
    //       "code": "invalid_type",
    //       "path": [ "maxResults" ],
    //       "message": "Invalid input: expected number, received string"
    //     }
    //   ]
    const content = result.content as Array<{ type: string; text: string }>;

    expect(result.isError).toBe(true);
    expect(content[0]!.text).toContain("MCP error -32602");
    expect(content[0]!.text).toContain("Invalid arguments for tool search");
    expect(content[0]!.text).toContain('"path": [\n      "maxResults"\n    ]');
    expect(content[0]!.text).toContain(
      '"message": "Invalid input: expected number, received string"',
    );
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('[92b] latitude passed as a STRING ("41.1") instead of a number — observed Zod/MCP SDK behavior', async () => {
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

    // Same behavior as [92]: rejected server-side by Zod, surfaced as a normal
    // (non-throwing) tool result with isError: true.
    const content = result.content as Array<{ type: string; text: string }>;

    expect(result.isError).toBe(true);
    expect(content[0]!.text).toContain("MCP error -32602");
    expect(content[0]!.text).toContain('"path": [\n      "latitude"\n    ]');
    expect(content[0]!.text).toContain(
      '"message": "Invalid input: expected number, received string"',
    );
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
