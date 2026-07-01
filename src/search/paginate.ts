import { buildSearchRequest } from "./request.js";
import { normalizeItem, type Listing } from "./listing.js";
import type {
  RawSearchItem,
  RawSearchResponse,
  SearchToolInput,
} from "./types.js";

const DEFAULT_MAX_RESULTS = 40;
const MAX_RESULTS_CAP = 200;

function extractItems(body: RawSearchResponse): RawSearchItem[] {
  const data = body.data;
  if (!data) {
    throw new Error("Malformed Wallapop response: missing data");
  }
  const section = data.section;
  if (!section) {
    throw new Error("Malformed Wallapop response: missing data.section");
  }
  const payload = section.payload;
  if (!payload) {
    throw new Error(
      "Malformed Wallapop response: missing data.section.payload",
    );
  }
  const items = payload.items;
  if (items === undefined) {
    throw new Error(
      "Malformed Wallapop response: missing data.section.payload.items",
    );
  }
  if (!Array.isArray(items)) {
    throw new Error(
      "Malformed Wallapop response: data.section.payload.items is not an array",
    );
  }
  return items;
}

export interface SearchListingsResult {
  listings: Listing[];
  nextPage: string | undefined;
}

export interface SearchListingsOptions {
  fetchImpl: (
    url: URL,
    init: { headers: Record<string, string> },
  ) => Promise<{
    ok: boolean;
    status: number;
    json: () => Promise<RawSearchResponse>;
  }>;
}

export async function searchListings(
  input: SearchToolInput,
  { fetchImpl }: SearchListingsOptions,
): Promise<SearchListingsResult> {
  const maxResults = Math.min(
    input.maxResults ?? DEFAULT_MAX_RESULTS,
    MAX_RESULTS_CAP,
  );

  const listings: Listing[] = [];
  let cursor = input.nextPage;
  let lastNextPage: string | undefined;

  while (listings.length < maxResults) {
    const { url, headers } = buildSearchRequest({ ...input, nextPage: cursor });
    const response = await fetchImpl(url, { headers });
    if (!response.ok) {
      throw new Error(
        `Wallapop search request failed: HTTP ${response.status}`,
      );
    }
    const body = await response.json();
    const items = extractItems(body);

    for (const raw of items) {
      if (listings.length >= maxResults) break;
      listings.push(normalizeItem(raw));
    }

    lastNextPage = body.meta?.next_page;
    if (!lastNextPage || items.length === 0) break;
    cursor = lastNextPage;
  }

  return { listings, nextPage: lastNextPage };
}
