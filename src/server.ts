import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { generatedCategories } from "./categories/generated.js";
import { searchCategories } from "./categories/search.js";
import {
  searchListings,
  type SearchListingsOptions,
} from "./search/paginate.js";

export interface CreateServerDeps {
  fetchImpl?: SearchListingsOptions["fetchImpl"];
}

export function createServer(deps: CreateServerDeps = {}): McpServer {
  const fetchImpl =
    deps.fetchImpl ?? (fetch as SearchListingsOptions["fetchImpl"]);

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

  server.registerTool(
    "search",
    {
      description:
        "Search Wallapop's marketplace. Defaults to the Barcelona-center location when latitude/longitude are omitted.",
      inputSchema: {
        keywords: z.string().optional(),
        categoryId: z.number().optional(),
        minPrice: z.number().optional(),
        maxPrice: z.number().optional(),
        distanceInKm: z.number().optional(),
        orderBy: z.string().optional(),
        latitude: z.number().optional(),
        longitude: z.number().optional(),
        nextPage: z
          .string()
          .optional()
          .describe(
            "Opaque pagination cursor from a previous search's response.",
          ),
        maxResults: z
          .number()
          .optional()
          .describe("Default 40, clamped to a 200 cap."),
      },
    },
    async (input) => {
      const result = await searchListings(input, { fetchImpl });
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
      };
    },
  );

  return server;
}
