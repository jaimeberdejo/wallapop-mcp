import { describe, expect, it } from "vitest";
import { flattenCategories } from "../../src/categories/flatten.js";
import type { RawCategoryNode } from "../../src/categories/types.js";

const fixture: RawCategoryNode[] = [
  {
    id: 100,
    name: "Cars",
    subcategories: [],
  },
  {
    id: 200,
    name: "Motors & accessories",
    subcategories: [
      {
        id: 210,
        name: "Car & van spare parts",
        subcategories: [
          {
            id: 211,
            name: "Accessories",
            subcategories: [],
          },
        ],
      },
    ],
  },
];

describe("flattenCategories", () => {
  it("flattens a top-level category with an empty ancestor path", () => {
    const result = flattenCategories(fixture);
    expect(result).toContainEqual({ id: 100, name: "Cars", path: [] });
  });

  it("builds the full ancestor path, not just the immediate parent", () => {
    const result = flattenCategories(fixture);
    expect(result).toContainEqual({
      id: 211,
      name: "Accessories",
      path: ["Motors & accessories", "Car & van spare parts"],
    });
  });

  it("includes intermediate nodes as their own entries", () => {
    const result = flattenCategories(fixture);
    expect(result).toContainEqual({
      id: 210,
      name: "Car & van spare parts",
      path: ["Motors & accessories"],
    });
  });

  it("produces one entry per node in the tree", () => {
    const result = flattenCategories(fixture);
    expect(result).toHaveLength(4);
  });
});
