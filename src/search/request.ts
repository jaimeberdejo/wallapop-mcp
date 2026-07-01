import { BARCELONA_CENTER } from "./barcelona.js";
import type { BuiltSearchRequest, SearchInput } from "./types.js";

const SEARCH_URL = "https://api.wallapop.com/api/v3/search";

// Hardcoded, non-configurable per the spec — not derived from SearchInput.
const REQUEST_HEADERS: Record<string, string> = {
  "User-Agent": "Mozilla/5.0",
  "X-DeviceOS": "0",
  Origin: "https://es.wallapop.com",
  Referer: "https://es.wallapop.com/",
};

// Required by the live endpoint (confirmed empirically — every request lacking these
// returned 400) but not meaningfully caller-configurable, so fixed like the headers.
const FIXED_PARAMS: Record<string, string> = {
  filters_source: "quick_filters",
  source: "search_box",
};

export function buildSearchRequest(input: SearchInput): BuiltSearchRequest {
  const url = new URL(SEARCH_URL);
  const params = url.searchParams;

  if (input.keywords !== undefined) params.set("keywords", input.keywords);
  if (input.categoryId !== undefined)
    params.set("category_ids", String(input.categoryId));
  if (input.minPrice !== undefined)
    params.set("min_sale_price", String(input.minPrice));
  if (input.maxPrice !== undefined)
    params.set("max_sale_price", String(input.maxPrice));
  if (input.distanceInKm !== undefined)
    params.set("distance", String(input.distanceInKm * 1000));
  if (input.orderBy !== undefined) params.set("order_by", input.orderBy);
  if (input.nextPage !== undefined) params.set("next_page", input.nextPage);

  const latitude = input.latitude ?? BARCELONA_CENTER.latitude;
  const longitude = input.longitude ?? BARCELONA_CENTER.longitude;
  params.set("latitude", String(latitude));
  params.set("longitude", String(longitude));

  for (const [key, value] of Object.entries(FIXED_PARAMS)) {
    params.set(key, value);
  }

  return { url, headers: { ...REQUEST_HEADERS } };
}
