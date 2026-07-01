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

function jsonResponse(body: unknown) {
  return {
    ok: true,
    status: 200,
    json: async () => body,
  } as unknown as Response;
}

function errorResponse(status: number) {
  return {
    ok: false,
    status,
    json: async () => ({ status, message: "", errors: [] }),
  } as unknown as Response;
}

describe("searchListings — upstream malformed/failure responses", () => {
  it("[71] rejects with a clear message on HTTP 400", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(errorResponse(400));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/wallapop search request failed.*400/i);
  });

  it("[72] rejects with a clear message on HTTP 403", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(errorResponse(403));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/wallapop search request failed.*403/i);
  });

  it("[73] rejects with a clear message on HTTP 429 (rate limited, no Retry-After handling)", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(errorResponse(429));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/wallapop search request failed.*429/i);
  });

  it("[74] rejects with a clear message on HTTP 500", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(errorResponse(500));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/wallapop search request failed.*500/i);
  });

  it("[75] propagates a network-level failure (DNS/connection error) unmodified", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new TypeError("fetch failed"));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow("fetch failed");
  });

  it("[76] propagates a response.json() parse failure (invalid JSON) unmodified", async () => {
    const fetchImpl = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.reject(new SyntaxError("Unexpected token in JSON")),
    } as unknown as Response);

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow("Unexpected token in JSON");
  });

  it("[77] body missing `data` entirely throws a raw TypeError, not a clear message", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({}));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(TypeError);
  });

  it("[78] body has `data: {}` (missing section) throws a raw TypeError", async () => {
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse({ data: {} }));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(TypeError);
  });

  it("[79] body has `data: { section: {} }` (missing payload) throws a raw TypeError", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse({ data: { section: {} } }));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(TypeError);
  });

  it("[80] body has `data: { section: { payload: {} } }` (missing items) throws a raw TypeError", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(jsonResponse({ data: { section: { payload: {} } } }));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(TypeError);
  });

  it("[81] an item with an empty images array rejects end-to-end with a clear, item-identifying error", async () => {
    const badItem = { ...rawItem("bad"), images: [] };
    const fetchImpl = vi.fn().mockResolvedValue(jsonResponse(page([badItem])));

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/malformed wallapop item bad.*images/i);
  });

  it("[82] an item missing the `price` field entirely rejects end-to-end with a clear, item-identifying error", async () => {
    const goodItem = rawItem("good") as Partial<RawSearchItem>;
    delete goodItem.price;
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(
        jsonResponse(page([goodItem as unknown as RawSearchItem])),
      );

    await expect(
      searchListings({ keywords: "iphone" }, { fetchImpl }),
    ).rejects.toThrow(/malformed wallapop item good.*price/i);
  });
});
