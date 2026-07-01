import { describe, expect, it } from "vitest";
import { searchCategories } from "../../src/categories/search.js";
import type { Category } from "../../src/categories/types.js";

const categories: Category[] = [
  { id: 100, name: "Cars", path: [] },
  { id: 200, name: "Motors & accessories", path: [] },
  { id: 210, name: "Car & van spare parts", path: ["Motors & accessories"] },
  {
    id: 211,
    name: "Accessories",
    path: ["Motors & accessories", "Car & van spare parts"],
  },
];

describe("searchCategories", () => {
  it("returns only top-level categories when no query is given", () => {
    expect(searchCategories(categories)).toEqual([
      { id: 100, name: "Cars", path: [] },
      { id: 200, name: "Motors & accessories", path: [] },
    ]);
  });

  it("matches by case-insensitive substring across all depths", () => {
    const result = searchCategories(categories, "car");
    expect(result.map((c) => c.id).sort()).toEqual([100, 210]);
  });

  it("returns an empty array when nothing matches", () => {
    expect(searchCategories(categories, "nonexistent")).toEqual([]);
  });
});
