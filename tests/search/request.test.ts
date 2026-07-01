import { describe, expect, it } from "vitest";
import { buildSearchRequest } from "../../src/search/request.js";
import { BARCELONA_CENTER } from "../../src/search/barcelona.js";

describe("buildSearchRequest", () => {
  it("maps the full parameter surface to query params and hardcoded headers", () => {
    const { url, headers } = buildSearchRequest({
      keywords: "iphone",
      categoryId: 12465,
      minPrice: 100,
      maxPrice: 500,
      distanceInKm: 20,
      orderBy: "newest",
      latitude: 41.1,
      longitude: 1.2,
      nextPage: "opaque-cursor-token",
    });

    expect(url.searchParams.get("keywords")).toBe("iphone");
    expect(url.searchParams.get("category_ids")).toBe("12465");
    expect(url.searchParams.get("min_sale_price")).toBe("100");
    expect(url.searchParams.get("max_sale_price")).toBe("500");
    expect(url.searchParams.get("distance")).toBe("20000");
    expect(url.searchParams.get("order_by")).toBe("newest");
    expect(url.searchParams.get("latitude")).toBe("41.1");
    expect(url.searchParams.get("longitude")).toBe("1.2");
    expect(url.searchParams.get("next_page")).toBe("opaque-cursor-token");
    expect(url.searchParams.get("filters_source")).toBe("quick_filters");
    expect(url.searchParams.get("source")).toBe("search_box");

    expect(headers).toEqual({
      "User-Agent": "Mozilla/5.0",
      "X-DeviceOS": "0",
      Origin: "https://es.wallapop.com",
      Referer: "https://es.wallapop.com/",
    });
  });

  it("defaults to the Barcelona-center location and omits unset optional params", () => {
    const { url } = buildSearchRequest({ keywords: "iphone" });

    expect(url.searchParams.get("keywords")).toBe("iphone");
    expect(url.searchParams.get("latitude")).toBe(
      String(BARCELONA_CENTER.latitude),
    );
    expect(url.searchParams.get("longitude")).toBe(
      String(BARCELONA_CENTER.longitude),
    );
    expect(url.searchParams.has("category_ids")).toBe(false);
    expect(url.searchParams.has("min_sale_price")).toBe(false);
    expect(url.searchParams.has("max_sale_price")).toBe(false);
    expect(url.searchParams.has("distance")).toBe(false);
    expect(url.searchParams.has("order_by")).toBe(false);
    expect(url.searchParams.has("next_page")).toBe(false);
    expect(url.searchParams.get("filters_source")).toBe("quick_filters");
    expect(url.searchParams.get("source")).toBe("search_box");
  });
});
