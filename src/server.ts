import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { generatedCategories } from "./categories/generated.js";
import { searchCategories } from "./categories/search.js";

export function createServer(): McpServer {
  const server = new McpServer({
    name: "wallapop-mcp",
    version: "0.1.0",
  });

  server.registerTool(
    "list_categories",
    {
      description:
        "Free-text search over Wallapop's category tree. With no query, returns the top-level categories.",
      inputSchema: {
        query: z
          .string()
          .optional()
          .describe(
            "Case-insensitive substring to match against category names.",
          ),
      },
    },
    ({ query }) => {
      const results = searchCategories(generatedCategories, query);
      return {
        content: [{ type: "text", text: JSON.stringify(results) }],
      };
    },
  );

  return server;
}
