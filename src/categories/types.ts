export interface Category {
  id: number;
  name: string;
  /** Ancestor names, root-first, excluding this category. Empty for a top-level category. */
  path: string[];
}

export interface RawCategoryNode {
  id: number;
  name: string;
  subcategories: RawCategoryNode[];
}
