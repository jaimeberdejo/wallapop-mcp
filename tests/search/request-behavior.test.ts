import { describe, expect, it } from "vitest";
import { buildSearchRequest } from "../../src/search/request.js";
import { BARCELONA_CENTER } from "../../src/search/barcelona.js";

describe("buildSearchRequest behavior", () => {
  it("[31] only keywords set -> keywords present, lat/lng default to Barcelona, no other optional params", () => {
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
  });

  it("[32] no coordinates at all -> latitude/longitude equal Barcelona center exactly", () => {
    const withKeywords = buildSearchRequest({ keywords: "iphone" });
    expect(withKeywords.url.searchParams.get("latitude")).toBe(
      String(BARCELONA_CENTER.latitude),
    );
    expect(withKeywords.url.searchParams.get("longitude")).toBe(
      String(BARCELONA_CENTER.longitude),
    );

    const empty = buildSearchRequest({});
    expect(empty.url.searchParams.get("latitude")).toBe(
      String(BARCELONA_CENTER.latitude),
    );
    expect(empty.url.searchParams.get("longitude")).toBe(
      String(BARCELONA_CENTER.longitude),
    );
  });

  it("[33] explicit latitude:0, longitude:0 is not overwritten by the Barcelona default", () => {
    const { url } = buildSearchRequest({ latitude: 0, longitude: 0 });

    expect(url.searchParams.get("latitude")).toBe("0");
    expect(url.searchParams.get("longitude")).toBe("0");
    expect(url.searchParams.get("latitude")).not.toBe(
      String(BARCELONA_CENTER.latitude),
    );
    expect(url.searchParams.get("longitude")).not.toBe(
      String(BARCELONA_CENTER.longitude),
    );
  });

  it("[34] categoryId maps to category_ids", () => {
    const { url } = buildSearchRequest({ categoryId: 12465 });
    expect(url.searchParams.get("category_ids")).toBe("12465");
  });

  it("[35] minPrice maps to min_sale_price", () => {
    const { url } = buildSearchRequest({ minPrice: 100 });
    expect(url.searchParams.get("min_sale_price")).toBe("100");
  });

  it("[36] maxPrice maps to max_sale_price", () => {
    const { url } = buildSearchRequest({ maxPrice: 500 });
    expect(url.searchParams.get("max_sale_price")).toBe("500");
  });

  it("[37] distanceInKm converts to meters for distance", () => {
    const { url } = buildSearchRequest({ distanceInKm: 20 });
    expect(url.searchParams.get("distance")).toBe("20000");
  });

  it("[38] orderBy passes through verbatim, unvalidated (no allowlist)", () => {
    const known = buildSearchRequest({ orderBy: "price_low_to_high" });
    expect(known.url.searchParams.get("order_by")).toBe("price_low_to_high");

    const bogus = buildSearchRequest({ orderBy: "bogus_order" });
    expect(bogus.url.searchParams.get("order_by")).toBe("bogus_order");
  });

  it("[39] nextPage passes through untouched as an opaque cursor", () => {
    const { url } = buildSearchRequest({
      nextPage: "opaque-cursor-token-abc123",
    });
    expect(url.searchParams.get("next_page")).toBe(
      "opaque-cursor-token-abc123",
    );
  });

  it("[40] fixed headers are always present with exact values, unaffected by input", () => {
    const expectedHeaders = {
      "User-Agent": "Mozilla/5.0",
      "X-DeviceOS": "0",
      Origin: "https://es.wallapop.com",
      Referer: "https://es.wallapop.com/",
    };

    const empty = buildSearchRequest({});
    expect(empty.headers).toEqual(expectedHeaders);

    const full = buildSearchRequest({
      keywords: "anything",
      categoryId: 1,
      minPrice: 1,
      maxPrice: 2,
      distanceInKm: 3,
      orderBy: "whatever",
      latitude: 10,
      longitude: 20,
      nextPage: "cursor",
    });
    expect(full.headers).toEqual(expectedHeaders);
  });

  it("[41] filters_source and source are always present and cannot be overridden (no such SearchInput field)", () => {
    const empty = buildSearchRequest({});
    expect(empty.url.searchParams.get("filters_source")).toBe("quick_filters");
    expect(empty.url.searchParams.get("source")).toBe("search_box");

    const full = buildSearchRequest({
      keywords: "test",
      categoryId: 1,
      minPrice: 1,
      maxPrice: 2,
      distanceInKm: 3,
      orderBy: "whatever",
      latitude: 10,
      longitude: 20,
      nextPage: "cursor",
    });
    expect(full.url.searchParams.get("filters_source")).toBe("quick_filters");
    expect(full.url.searchParams.get("source")).toBe("search_box");
  });

  it("[42] keywords with embedded spaces round-trip exactly and are percent-encoded in the raw URL", () => {
    const { url } = buildSearchRequest({ keywords: "iphone 13 pro" });

    expect(url.searchParams.get("keywords")).toBe("iphone 13 pro");
    const raw = url.toString();
    const encodedFragment = /keywords=iphone(%20|\+)13(%20|\+)pro/;
    expect(raw).toMatch(encodedFragment);
    expect(raw).not.toContain("keywords=iphone 13 pro");
  });

  it("[43] keywords with unicode/accents round-trip exactly", () => {
    const { url } = buildSearchRequest({ keywords: "cámara réflex ñ" });
    expect(url.searchParams.get("keywords")).toBe("cámara réflex ñ");
  });

  it("[44] keywords with symbols including + and / round-trip exactly", () => {
    const { url } = buildSearchRequest({
      keywords: "iphone 13 + funda / 128gb",
    });
    expect(url.searchParams.get("keywords")).toBe("iphone 13 + funda / 128gb");
  });

  it("[45] keywords containing raw &/= (injection attempt) do not create extra query params", () => {
    const { url } = buildSearchRequest({
      keywords: "iphone&latitude=0&extra=1",
    });

    expect(url.searchParams.get("keywords")).toBe("iphone&latitude=0&extra=1");
    expect(url.searchParams.getAll("keywords")).toHaveLength(1);
    expect(url.searchParams.has("extra")).toBe(false);
    expect(url.searchParams.get("latitude")).toBe(
      String(BARCELONA_CENTER.latitude),
    );
    expect(url.searchParams.get("latitude")).not.toBe("0");
  });
});
