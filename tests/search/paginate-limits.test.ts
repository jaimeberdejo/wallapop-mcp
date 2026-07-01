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

function itemsOf(count: number, prefix = "p"): RawSearchItem[] {
  return Array.from({ length: count }, (_, i) => rawItem(`${prefix}-${i}`));
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

describe("searchListings — limits and pagination edge cases", () => {
  it("[46] default maxResults (omitted) with a single 40-item page and no next_page returns exactly 40, 1 fetch call", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40))));

    const result = await searchListings({ keywords: "iphone" }, { fetchImpl });

    expect(result.listings).toHaveLength(40);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("[47] maxResults: 1 with a many-item page stops mid-page after exactly 1 fetch call", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40), "cursor-next")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 1 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(1);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("[48] maxResults: 39 with a 40-item page returns exactly 39", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40))));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 39 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(39);
  });

  it("[49] maxResults: 40 with exactly a 40-item page and no next_page returns exactly 40, 1 fetch call", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40))));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 40 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(40);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("[50] maxResults: 41 forces a second fetch call, total 41 listings", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p1"), "cursor-1")))
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p2"))));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 41 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(41);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it("[51] maxResults: 200 across 5 pages of 40 items returns exactly 200 and calls fetch 5 times", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p1"), "c1")))
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p2"), "c2")))
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p3"), "c3")))
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p4"), "c4")))
      .mockResolvedValueOnce(jsonResponse(page(itemsOf(40, "p5"), "c5")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 200 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(200);
    expect(fetchImpl).toHaveBeenCalledTimes(5);
  });

  it("[52] maxResults: 201 is clamped to 200, not 201", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40), "cursor-next")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 201 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(200);
  });

  it("[53] maxResults: 500 is clamped to 200, fetchImpl called at most ceil(200/40)=5 times", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(40), "cursor-next")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 500 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(200);
    expect(fetchImpl.mock.calls.length).toBeLessThanOrEqual(5);
  });

  it("[54] a page with items but no next_page in meta stops the loop after 1 fetch call, even under maxResults", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page(itemsOf(10))));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 40 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(10);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("[55] a page with next_page present but items: [] stops immediately — 1 fetch call, 0 listings", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse(page([], "cursor-next")));

    const result = await searchListings(
      { keywords: "iphone", maxResults: 40 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(0);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("[56] an opaque base64-looking cursor passed as input.nextPage is forwarded unmodified to the first fetch call's next_page param", async () => {
    const opaqueCursor = "eyJvZmZzZXQiOjQwfQ==";
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse(page(itemsOf(5))));

    await searchListings(
      { keywords: "iphone", nextPage: opaqueCursor, maxResults: 5 },
      { fetchImpl },
    );

    const firstCallUrl = fetchImpl.mock.calls[0]![0] as URL;
    expect(firstCallUrl.searchParams.get("next_page")).toBe(opaqueCursor);
  });

  it("[57] a cursor with special characters round-trips exactly through buildSearchRequest/URLSearchParams", async () => {
    const weirdCursor = "cursor+with/slashes=and&weird?chars#here";
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse(page(itemsOf(5))));

    await searchListings(
      { keywords: "iphone", nextPage: weirdCursor, maxResults: 5 },
      { fetchImpl },
    );

    const firstCallUrl = fetchImpl.mock.calls[0]![0] as URL;
    expect(firstCallUrl.searchParams.get("next_page")).toBe(weirdCursor);
  });

  it("[58] loop terminates against a buggy upstream that always returns the same next_page cursor and non-empty items", async () => {
    // Design note: the ONLY termination guarantee in searchListings is the
    // `listings.length < maxResults` while-loop condition. There is no
    // independent max-page-count / max-iteration safety net. That is fine
    // today because maxResults is always clamped to <= 200 (MAX_RESULTS_CAP),
    // so the loop is bounded by at most ceil(200 / itemsPerPage) iterations.
    // If that cap were ever removed or maxResults became unbounded, an
    // upstream that never returns items.length === 0 and never stops handing
    // back a next_page cursor (as simulated here) would hang forever.
    const itemsPerPage = 40;
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(
        jsonResponse(page(itemsOf(itemsPerPage), "same-cursor-forever")),
      );

    const result = await searchListings(
      { keywords: "iphone", maxResults: 200 },
      { fetchImpl },
    );

    expect(result.listings.length).toBeLessThanOrEqual(200);
    expect(fetchImpl.mock.calls.length).toBeLessThanOrEqual(
      Math.ceil(200 / itemsPerPage),
    );
  });

  it("[90] maxResults: 0 returns 0 listings and never calls fetchImpl", async () => {
    const fetchImpl = vi.fn();

    const result = await searchListings(
      { keywords: "iphone", maxResults: 0 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(0);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("[91] maxResults: -5 (negative) returns 0 listings and never calls fetchImpl — not rejected as invalid input", async () => {
    const fetchImpl = vi.fn();

    const result = await searchListings(
      { keywords: "iphone", maxResults: -5 },
      { fetchImpl },
    );

    expect(result.listings).toHaveLength(0);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
