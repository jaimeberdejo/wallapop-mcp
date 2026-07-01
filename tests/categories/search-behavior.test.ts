import { describe, expect, it } from "vitest";
import { searchCategories } from "../../src/categories/search.js";
import { generatedCategories } from "../../src/categories/generated.js";
import type { Category } from "../../src/categories/types.js";

describe("searchCategories behavior audit (cases 21-30)", () => {
  it("[21] no query returns only top-level categories (path.length === 0)", () => {
    const result = searchCategories(generatedCategories);
    const expected = generatedCategories.filter((c) => c.path.length === 0);

    expect(result).toHaveLength(expected.length);
    expect(result.map((c) => c.id).sort((a, b) => a - b)).toEqual(
      expected.map((c) => c.id).sort((a, b) => a - b),
    );
    expect(result.every((c) => c.path.length === 0)).toBe(true);
  });

  it("[22] query is case-insensitive: 'tech' and 'TECH' return identical result sets", () => {
    const lower = searchCategories(generatedCategories, "tech");
    const upper = searchCategories(generatedCategories, "TECH");

    expect(lower.length).toBeGreaterThan(0);
    expect(upper.map((c) => c.id)).toEqual(lower.map((c) => c.id));
    expect(upper).toEqual(lower);
  });

  it("[23] does NOT accent-fold: an accent-stripped query fails to match an accented name", () => {
    // Discovery note: generated.ts (English-locale Wallapop category tree) contains
    // zero accented characters (verified via grep for ó/é/í/á/ñ and uppercase variants),
    // so we can't demonstrate this against generatedCategories directly. We use a small
    // local fixture with an accented category name instead, exercising the same
    // searchCategories implementation.
    const fixture: Category[] = [
      { id: 1, name: "Música", path: ["Hobbies & culture"] },
    ];

    const strippedQueryResult = searchCategories(fixture, "musica");
    const accentedQueryResult = searchCategories(fixture, "música");

    // Current actual behavior: plain .toLowerCase() + .includes() does no Unicode
    // normalization/accent-folding, so "musica" does NOT match "Música".
    expect(strippedQueryResult).toEqual([]);
    expect(accentedQueryResult).toEqual(fixture);
    // Improvement note: accent-insensitive matching (e.g. normalizing both sides with
    // String.prototype.normalize("NFD") and stripping diacritics) would likely be more
    // forgiving for LLM-generated queries, which may drop accents.
  });

  it("[24] does NOT trim lateral whitespace from the query", () => {
    // Read search.ts: `query.toLowerCase()` is used verbatim as the substring needle,
    // with no .trim() call anywhere. A query padded with spaces becomes a needle padded
    // with spaces, which will only match names that themselves contain that literal
    // padding — i.e. for ordinary category names, a padded query matches nothing.
    const padded = searchCategories(generatedCategories, "  tech  ");
    const unpadded = searchCategories(generatedCategories, "tech");

    expect(unpadded.length).toBeGreaterThan(0);
    expect(padded).toEqual([]);
    // Improvement note: trimming the query before matching would make search more
    // forgiving for LLM-generated queries, which sometimes include incidental whitespace.
  });

  it("[25] empty string query behaves the same as no query (top-level only)", () => {
    const withEmptyString = searchCategories(generatedCategories, "");
    const withNoQuery = searchCategories(generatedCategories);

    expect(withEmptyString).toEqual(withNoQuery);
    expect(withEmptyString.every((c) => c.path.length === 0)).toBe(true);
  });

  it("[26] a query matching nothing returns an empty array", () => {
    const result = searchCategories(
      generatedCategories,
      "zzzznonexistentcategoryzzzz",
    );
    expect(result).toEqual([]);
  });

  it("[27] a query matching only a deep (depth >= 2) category returns it with the correct path", () => {
    // "Car security" (id 10335) lives at Motors & accessories > Car & van spare parts,
    // i.e. path.length === 2, and its name is unique across the whole tree.
    const result = searchCategories(generatedCategories, "Car security");

    expect(result).toEqual([
      {
        id: 10335,
        name: "Car security",
        path: ["Motors & accessories", "Car & van spare parts"],
      },
    ]);
    expect(result[0]?.path.length).toBeGreaterThanOrEqual(2);
  });

  it("[28] every category has a defined numeric id, non-empty string name, and array path", () => {
    for (const category of generatedCategories) {
      expect(typeof category.id).toBe("number");
      expect(category.id).toBeDefined();
      expect(typeof category.name).toBe("string");
      expect(category.name.length).toBeGreaterThan(0);
      expect(Array.isArray(category.path)).toBe(true);
    }
  });

  it("[29] a category's own name generally does not appear as the last element of its own path", () => {
    // Spot check a handful of known entries first.
    const sample = generatedCategories.slice(0, 20);
    for (const category of sample) {
      expect(category.path.at(-1)).not.toBe(category.name);
    }

    // Full-array invariant check. This is NOT guaranteed to be empty: flattenCategories
    // always excludes *structural* self-reference (a node never contains its own id in
    // its path), but nothing stops two different category ids from sharing the same
    // *name* at adjacent levels. In the real Wallapop tree there is exactly one such
    // case: category id 10067 "Movies & series" is itself a child of a category also
    // named "Movies & series" (under "Movies, books & music"), so its path ends with
    // its own name even though it is a distinct node. We assert the known, current
    // shape of that exception rather than asserting a false invariant.
    const violations = generatedCategories.filter(
      (category) => category.path.at(-1) === category.name,
    );
    expect(violations).toEqual([
      {
        id: 10067,
        name: "Movies & series",
        path: ["Movies, books & music", "Movies & series"],
      },
    ]);
  });

  it("[30] no duplicate id values exist in generatedCategories", () => {
    const ids = generatedCategories.map((c) => c.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(ids.length);
  });
});
