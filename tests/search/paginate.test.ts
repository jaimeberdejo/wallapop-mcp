import { describe, expect, it, vi } from "vitest";
import { searchListings } from "../../src/search/paginate.js";
import type {
  RawSearchItem,
  RawSearchResponse,
} from "../../src/search/types.js";

function rawItem(id: string): RawSearchItem {
  return {
    id,
    title: `Item ${id}`,
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
    web_slug: `slug-${id}`,
    created_at: 1700000000000,
  };
}

function page(items: RawSearchItem[], nextPage?: string): RawSearchResponse {
  return {
    data: { section: { payload: { items } } },
    meta: nextPage ? { next_page: nextPage } : {},
  };
}

function jsonResponse(body: RawSearchResponse) {
  return { ok: true, status: 200, json: async () => body } as Response;
}

function errorResponse(status: number) {
  return {
    ok: false,
    status,
    json: async () => ({ status, message: "", errors: [] }),
  } as unknown as Response;
}

describe("searchListings", () => {
  it("stops accumulating once maxResults is reached, even with more pages available", async () => {
    const pageOne = Array.from({ length: 40 }, (_, i) => rawItem(`p1-${i}`));
    const pageTwo = Array.from({ length: 40 }, (_, i) => rawItem(`p2-${i}`));
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page(pageOne, "cursor-1")))
      .mockResolvedValueOnce(jsonResponse(page(pageTwo, "cursor-2")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 50 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(50);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it("clamps a requested maxResults above 200 down to 200", async () => {
    const bigPage = Array.from({ length: 40 }, (_, i) => rawItem(`p-${i}`));
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(bigPage, "cursor-next")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 500 },
      { fetchImpl },
    );

    expect(result.listings.length).toBeLessThanOrEqual(200);
    expect(result.listings).toHaveLength(200);
  });

  it("passes the previous page's next_page cursor through untouched, unmodified", async () => {
    const pageOne = Array.from({ length: 40 }, (_, i) => rawItem(`p1-${i}`));
    const pageTwo = Array.from({ length: 5 }, (_, i) => rawItem(`p2-${i}`));
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page(pageOne, "opaque-cursor-xyz")))
      .mockResolvedValueOnce(jsonResponse(page(pageTwo)));

    await searchListings({ keywords: "iphone", maxResults: 45 }, { fetchImpl });

    const secondCallUrl = fetchImpl.mock.calls[1]![0] as URL;
    expect(secondCallUrl.searchParams.get("next_page")).toBe(
      "opaque-cursor-xyz",
    );
  });

  it("stops when a page has no next_page and no more items", async () => {
    const onlyPage = Array.from({ length: 5 }, (_, i) => rawItem(`p-${i}`));
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse(page(onlyPage)));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 40 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(5);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("throws a clear error on a non-2xx upstream response, instead of silently misreading the error body as data", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(errorResponse(400));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/wallapop search request failed.*400/i);
  });

  it("propagates a network-level failure instead of swallowing it", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new TypeError("fetch failed"));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow("fetch failed");
  });
});
