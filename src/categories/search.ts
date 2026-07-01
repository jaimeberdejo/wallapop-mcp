import type { Category } from "./types.js";

function normalizeSearchText(value: string): string {
  return value.trim().normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

export function searchCategories(
  categories: Category[],
  query?: string,
): Category[] {
  const trimmedQuery = query?.trim();
  if (!trimmedQuery) {
    return categories.filter((category) => category.path.length === 0);
  }

  const needle = normalizeSearchText(trimmedQuery);
  return categories.filter((category) =>
    normalizeSearchText(category.name).includes(needle),
  );
}
