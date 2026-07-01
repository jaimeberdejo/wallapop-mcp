import type { Category } from "./types.js";

export function searchCategories(
  categories: Category[],
  query?: string,
): Category[] {
  if (!query) {
    return categories.filter((category) => category.path.length === 0);
  }

  const needle = query.toLowerCase();
  return categories.filter((category) =>
    category.name.toLowerCase().includes(needle),
  );
}
