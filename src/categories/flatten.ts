import type { Category, RawCategoryNode } from "./types.js";

export function flattenCategories(
  nodes: RawCategoryNode[],
  ancestorPath: string[] = [],
): Category[] {
  return nodes.flatMap((node) => [
    { id: node.id, name: node.name, path: ancestorPath },
    ...flattenCategories(node.subcategories, [...ancestorPath, node.name]),
  ]);
}
