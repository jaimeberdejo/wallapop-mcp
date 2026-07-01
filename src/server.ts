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
        "Free-text, case-insensitive, accent- and whitespace-insensitive search over Wallapop's static category tree. Use it to resolve a category name to the numeric categoryId accepted by the search tool's categoryId argument. With no query (or an empty/whitespace-only query), returns only the top-level categories.",
      inputSchema: {
        query: z
          .string()
          .optional()
          .describe(
            "Case-insensitive, accent- and whitespace-insensitive substring to match against category names.",
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
        "Search Wallapop's marketplace listings. Read-only: no login, purchase, messaging, reservation, or favoriting is performed. Defaults to the Barcelona-center location when latitude/longitude are omitted. Returns up to maxResults listings (default 40, hard-capped at 200 even if a higher value is requested). Item condition (e.g. new/used) is rarely present in Wallapop's raw data — treat it as unreliable and do not tell the user results are filtered by condition.",
      inputSchema: {
        keywords: z
          .string()
          .optional()
          .describe("Free-text keywords, passed through to Wallapop as-is."),
        categoryId: z
          .number()
          .optional()
          .describe(
            "Numeric Wallapop category id (e.g. from list_categories) to restrict results to.",
          ),
        minPrice: z
          .number()
          .nonnegative()
          .optional()
          .describe(
            "Minimum price in EUR, inclusive. Must be zero or greater.",
          ),
        maxPrice: z
          .number()
          .nonnegative()
          .optional()
          .describe(
            "Maximum price in EUR, inclusive. Must be zero or greater, and must not be less than minPrice when both are given.",
          ),
        distanceInKm: z
          .number()
          .positive()
          .optional()
          .describe(
            "Search radius in kilometers from the search location. Must be greater than zero.",
          ),
        orderBy: z
          .string()
          .optional()
          .describe(
            'Sort order, passed through to Wallapop unvalidated (e.g. "price_low_to_high"). No enumerated list of legal values is confirmed here; an invalid value may be ignored or rejected upstream rather than erroring in this tool.',
          ),
        latitude: z
          .number()
          .min(-90)
          .max(90)
          .optional()
          .describe("Search latitude in decimal degrees, -90 to 90."),
        longitude: z
          .number()
          .min(-180)
          .max(180)
          .optional()
          .describe("Search longitude in decimal degrees, -180 to 180."),
        nextPage: z
          .string()
          .optional()
          .describe(
            "Opaque pagination cursor from a previous search response's nextPage field. Pass it back exactly as received (unmodified) to fetch the next page; do not construct or edit it.",
          ),
        maxResults: z
          .number()
          .int()
          .nonnegative()
          .optional()
          .describe("Default 40, clamped to a 200 cap."),
      },
    },
    async (input) => {
      if (
        input.minPrice !== undefined &&
        input.maxPrice !== undefined &&
        input.minPrice > input.maxPrice
      ) {
        throw new Error(
          `Invalid search input: minPrice (${input.minPrice}) must not exceed maxPrice (${input.maxPrice})`,
        );
      }
      const result = await searchListings(input, { fetchImpl });
      return {
        content: [{ type: "text", text: JSON.stringify(result) }],
      };
    },
  );

  return server;
}
