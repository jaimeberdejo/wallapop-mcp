import { buildSearchRequest } from "./request.js";
import { normalizeItem, type Listing } from "./listing.js";
import type { RawSearchResponse, SearchToolInput } from "./types.js";

const DEFAULT_MAX_RESULTS = 40;
const MAX_RESULTS_CAP = 200;

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
    const items = body.data.section.payload.items;

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
