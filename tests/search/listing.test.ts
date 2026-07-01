import { describe, expect, it } from "vitest";
import { normalizeItem } from "../../src/search/listing.js";
import type { RawSearchItem } from "../../src/search/types.js";

const fixtureItem: RawSearchItem = {
  id: "pzpko29729j3",
  title: "IPhone 17 Pro 512Gb Seminuevo",
  description: "En perfecto estado",
  price: { amount: 1199, currency: "EUR" },
  images: [
    {
      id: "nz0g2d3ym8vj",
      urls: {
        small: "https://cdn.wallapop.com/small.jpg",
        medium: "https://cdn.wallapop.com/medium.jpg",
        big: "https://cdn.wallapop.com/big.jpg",
      },
    },
  ],
  location: {
    latitude: 41.38447965689129,
    longitude: 2.1776382732640958,
    postal_code: "08001",
    city: "Barcelona",
    region: "Cataluña",
    country_code: "ES",
  },
  web_slug: "iphone-17-pro-512gb-seminuevo-1275712826",
  created_at: 1782392930564,
  reserved: { flag: false },
  favorited: { flag: false },
  bump: { type: "zone" },
  taxonomy: [{ id: 24200, name: "Technology & electronics", icon: "robot" }],
  is_favoriteable: { flag: true },
  is_refurbished: { flag: false },
  is_top_profile: { flag: false },
  has_warranty: { flag: false },
};

describe("normalizeItem", () => {
  it("maps a raw item to exactly the spec's Listing shape", () => {
    const listing = normalizeItem(fixtureItem);

    expect(listing).toEqual({
      id: "pzpko29729j3",
      title: "IPhone 17 Pro 512Gb Seminuevo",
      description: "En perfecto estado",
      price: 1199,
      currency: "EUR",
      imageUrl: "https://cdn.wallapop.com/big.jpg",
      url: "https://es.wallapop.com/item/iphone-17-pro-512gb-seminuevo-1275712826",
      location: { city: "Barcelona", postalCode: "08001", countryCode: "ES" },
      condition: undefined,
      createdAt: new Date(1782392930564).toISOString(),
    });
  });

  it("excludes Wallapop-internal presentation fields", () => {
    const listing = normalizeItem(fixtureItem);
    const keys = Object.keys(listing);

    for (const internal of [
      "bump",
      "favorited",
      "is_top_profile",
      "taxonomy",
    ]) {
      expect(keys).not.toContain(internal);
    }
  });

  it("reads condition when the raw item happens to have one", () => {
    const listing = normalizeItem({ ...fixtureItem, condition: "new" });
    expect(listing.condition).toBe("new");
  });
});
