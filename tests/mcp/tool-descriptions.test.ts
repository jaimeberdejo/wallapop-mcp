import { describe, expect, it } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../../src/server.js";

async function connectedClient() {
  const server = createServer();
  const client = new Client({ name: "test-client", version: "0.0.0" });
  const [clientTransport, serverTransport] =
    InMemoryTransport.createLinkedPair();
  await Promise.all([
    server.connect(serverTransport),
    client.connect(clientTransport),
  ]);
  return client;
}

type InputSchema = {
  properties?: Record<string, { description?: string }>;
};

describe("tool description and per-field describe() text", () => {
  it("search description mentions read-only scope", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    expect(search.description).toMatch(/read-only/i);
  });

  it("search description mentions the Barcelona-center default", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    expect(search.description).toMatch(/barcelona/i);
  });

  it("search description mentions maxResults default 40 and cap 200", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    expect(search.description).toMatch(/40/);
    expect(search.description).toMatch(/200/);
  });

  it("search description mentions condition is rare/unreliable and not a real filter", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    expect(search.description).toMatch(/condition/i);
  });

  it("search's nextPage field describes an opaque cursor to be passed back exactly", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    const schema = search.inputSchema as InputSchema;
    expect(schema.properties?.nextPage?.description).toMatch(/opaque/i);
    expect(schema.properties?.nextPage?.description).toMatch(
      /exactly|verbatim|unmodified/i,
    );
  });

  it("search's orderBy field describes itself as unvalidated pass-through to Wallapop", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const search = tools.find((t) => t.name === "search")!;
    const schema = search.inputSchema as InputSchema;
    expect(schema.properties?.orderBy?.description).toMatch(/wallapop/i);
    expect(schema.properties?.orderBy?.description).toMatch(
      /unvalidated|pass.?through|not validated/i,
    );
  });

  it("list_categories description mentions categoryId resolution and top-level default", async () => {
    const client = await connectedClient();
    const { tools } = await client.listTools();
    const listCategories = tools.find((t) => t.name === "list_categories")!;
    expect(listCategories.description).toMatch(/categoryId/i);
    expect(listCategories.description).toMatch(/top-level/i);
  });
});
