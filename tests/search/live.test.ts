import { describe, expect, it } from "vitest";
import {
  searchListings,
  type SearchListingsOptions,
} from "../../src/search/paginate.js";

// Opt-in: real calls to Wallapop's live API. Excluded from the default `pnpm test` run —
// run manually with `WALLAPOP_LIVE_TESTS=1 pnpm test`. Not part of CI.
describe.skipIf(!process.env.WALLAPOP_LIVE_TESTS)(
  "searchListings (live)",
  () => {
    it("returns a non-empty Listing[] for keywords: iphone with no location", async () => {
      const result = await searchListings(
        { keywords: "iphone" },
        { fetchImpl: fetch as SearchListingsOptions["fetchImpl"] },
      );

      expect(result.listings.length).toBeGreaterThan(0);
      expect(result.listings[0]).toMatchObject({
        id: expect.any(String),
        title: expect.any(String),
        price: expect.any(Number),
        currency: expect.any(String),
        url: expect.stringContaining("es.wallapop.com/item/"),
      });
    }, 15000);
  },
);
