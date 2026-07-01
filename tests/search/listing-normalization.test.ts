import { describe, expect, it } from "vitest";
import { normalizeItem } from "../../src/search/listing.js";
import type { RawSearchItem } from "../../src/search/types.js";

const baseFixture: RawSearchItem = {
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
};

describe("normalizeItem — field-by-field normalization", () => {
  it("[59] maps id correctly (exact passthrough)", () => {
    const item: RawSearchItem = { ...baseFixture, id: "abc-123-XYZ" };
    const listing = normalizeItem(item);
    expect(listing.id).toBe("abc-123-XYZ");
  });

  it("[60] maps title correctly, including special chars/emoji, without mangling", () => {
    const title = "¡Ganga! Bici 🚲 #1 (¡único!) — 50% dto.";
    const item: RawSearchItem = { ...baseFixture, title };
    const listing = normalizeItem(item);
    expect(listing.title).toBe(title);
  });

  it("[61] maps description correctly, including multi-line text with \\n", () => {
    const description = "Línea 1\nLínea 2\nEstado: como nuevo\n¡Envío rápido!";
    const item: RawSearchItem = { ...baseFixture, description };
    const listing = normalizeItem(item);
    expect(listing.description).toBe(description);
  });

  it("[62] maps price.amount -> top-level price field", () => {
    const item: RawSearchItem = {
      ...baseFixture,
      price: { amount: 42.5, currency: "EUR" },
    };
    const listing = normalizeItem(item);
    expect(listing.price).toBe(42.5);
  });

  it("[63] maps price.currency -> top-level currency field, not hardcoded to EUR", () => {
    const item: RawSearchItem = {
      ...baseFixture,
      price: { amount: 100, currency: "USD" },
    };
    const listing = normalizeItem(item);
    expect(listing.currency).toBe("USD");
  });

  it("[64] uses images[0].urls.big specifically, not .medium/.small, and not images[1]", () => {
    const item: RawSearchItem = {
      ...baseFixture,
      images: [
        {
          id: "first-image",
          urls: {
            small: "https://cdn.wallapop.com/img0-small.jpg",
            medium: "https://cdn.wallapop.com/img0-medium.jpg",
            big: "https://cdn.wallapop.com/img0-big.jpg",
          },
        },
        {
          id: "second-image",
          urls: {
            small: "https://cdn.wallapop.com/img1-small.jpg",
            medium: "https://cdn.wallapop.com/img1-medium.jpg",
            big: "https://cdn.wallapop.com/img1-big.jpg",
          },
        },
      ],
    };
    const listing = normalizeItem(item);
    expect(listing.imageUrl).toBe("https://cdn.wallapop.com/img0-big.jpg");
    expect(listing.imageUrl).not.toBe(
      "https://cdn.wallapop.com/img0-medium.jpg",
    );
    expect(listing.imageUrl).not.toBe(
      "https://cdn.wallapop.com/img0-small.jpg",
    );
    expect(listing.imageUrl).not.toBe("https://cdn.wallapop.com/img1-big.jpg");
  });

  it("[65] constructs url as https://es.wallapop.com/item/${web_slug} exactly", () => {
    const item: RawSearchItem = {
      ...baseFixture,
      web_slug: "mesa-de-comedor-6-sillas-1234567890",
    };
    const listing = normalizeItem(item);
    expect(listing.url).toBe(
      "https://es.wallapop.com/item/mesa-de-comedor-6-sillas-1234567890",
    );
  });

  it("[66] maps location fields correctly and excludes latitude/longitude/region", () => {
    const item: RawSearchItem = {
      ...baseFixture,
      location: {
        latitude: 40.4168,
        longitude: -3.7038,
        postal_code: "28013",
        city: "Madrid",
        region: "Comunidad de Madrid",
        country_code: "ES",
      },
    };
    const listing = normalizeItem(item);
    expect(listing.location).toEqual({
      city: "Madrid",
      postalCode: "28013",
      countryCode: "ES",
    });
    const locationKeys = Object.keys(listing.location);
    expect(locationKeys).not.toContain("latitude");
    expect(locationKeys).not.toContain("longitude");
    expect(locationKeys).not.toContain("region");
  });

  it("[67] converts created_at epoch ms to ISO 8601 string exactly", () => {
    const item: RawSearchItem = { ...baseFixture, created_at: 1700000000000 };
    const listing = normalizeItem(item);
    expect(listing.createdAt).toBe(new Date(1700000000000).toISOString());
    expect(listing.createdAt).toBe("2023-11-14T22:13:20.000Z");
  });

  it("[68] excludes all internal/presentation-only fields from the Listing object", () => {
    const internalFields = [
      "bump",
      "favorited",
      "taxonomy",
      "reserved",
      "shipping",
      "is_favoriteable",
      "is_refurbished",
      "is_top_profile",
      "has_warranty",
      "user_id",
      "category_id",
      "modified_at",
    ] as const;

    const item: RawSearchItem = {
      ...baseFixture,
      bump: { type: "zone" },
      favorited: { flag: true },
      taxonomy: [{ id: 1, name: "x", icon: "y" }],
      reserved: { flag: true },
      shipping: { flag: true },
      is_favoriteable: true,
      is_refurbished: true,
      is_top_profile: true,
      has_warranty: true,
      user_id: "u1",
      category_id: 100,
      modified_at: 1700000000000,
    };

    const listing = normalizeItem(item);
    const keys = Object.keys(listing);

    for (const field of internalFields) {
      expect(keys).not.toContain(field);
    }
  });

  it("[69] preserves condition when present on the raw item", () => {
    const item: RawSearchItem = { ...baseFixture, condition: "new" };
    const listing = normalizeItem(item);
    expect(listing.condition).toBe("new");
  });

  it("[70] condition absent vs explicitly undefined both read as undefined on the Listing (informational: 'in'/Object.keys differ)", () => {
    const itemAbsent: Partial<RawSearchItem> = {
      ...baseFixture,
      condition: "placeholder",
    };
    delete itemAbsent.condition;
    const itemExplicitUndefined: RawSearchItem = {
      ...baseFixture,
      condition: undefined,
    };

    const listingAbsent = normalizeItem(itemAbsent as RawSearchItem);
    const listingExplicit = normalizeItem(itemExplicitUndefined);

    expect(listingAbsent.condition).toBeUndefined();
    expect(listingExplicit.condition).toBeUndefined();

    // Informational note (not a bug): normalizeItem's return object literal explicitly assigns
    // `condition: raw.condition` (no spread, no conditional omission), so the 'condition' key is
    // always present on the returned Listing regardless of whether the raw item had the key at
    // all. So here Object.keys(listing).includes('condition') is true for BOTH input shapes —
    // "absent key" and "explicit undefined" are NOT distinguishable via Object.keys/'in' on the
    // output, only listing.condition's runtime value (undefined either way) can be observed.
    expect(Object.keys(listingAbsent).includes("condition")).toBe(true);
    expect(Object.keys(listingExplicit).includes("condition")).toBe(true);
  });
});

describe("normalizeItem — malformed-item error clarity", () => {
  // Originally, a missing `images`/`price` field produced a raw, unhelpful V8 TypeError
  // (e.g. "Cannot read properties of undefined (reading 'urls')") with no indication of
  // which item or field was at fault — bad for an LLM client trying to explain a tool
  // failure to a user. normalizeItem now throws a descriptive error naming the item id
  // and the missing field instead of letting the property access crash raw.
  it("[discovery] throws a clear, item-identifying error when images is an empty array", () => {
    const badItem: RawSearchItem = { ...baseFixture, images: [] };

    expect(() => normalizeItem(badItem)).toThrow(
      /malformed wallapop item.*images/i,
    );
    expect(() => normalizeItem(badItem)).toThrow(new RegExp(baseFixture.id));
  });

  it("[discovery] throws a clear, item-identifying error when price is missing entirely", () => {
    const badItem = { ...baseFixture } as Partial<RawSearchItem>;
    delete badItem.price;
    const item = badItem as RawSearchItem;

    expect(() => normalizeItem(item)).toThrow(
      /malformed wallapop item.*price/i,
    );
    expect(() => normalizeItem(item)).toThrow(new RegExp(baseFixture.id));
  });
});
