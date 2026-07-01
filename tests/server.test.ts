import { describe, expect, it } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { createServer } from "../src/server.js";
import { generatedCategories } from "../src/categories/generated.js";

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

describe("createServer", () => {
  it("lists the list_categories tool", async () => {
    const client = await connectedClient();

    const result = await client.listTools();

    expect(result.tools.map((tool) => tool.name)).toEqual(["list_categories"]);
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
});
