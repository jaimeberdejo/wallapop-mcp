// One-off codegen: fetches Wallapop's live category tree and flattens it into a static,
// checked-in TS module (src/categories/generated.ts). Not run as part of `pnpm build`/`pnpm
// test` — re-run by hand (`pnpm codegen:categories`) if the upstream taxonomy drifts.
// See docs/adr/0001-static-generated-category-tree.md.
import { writeFile } from "node:fs/promises";
import { flattenCategories } from "../src/categories/flatten.js";
import type { RawCategoryNode } from "../src/categories/types.js";

const CATEGORIES_URL = "https://api.wallapop.com/api/v3/categories";

interface RawCategoriesResponse {
  categories: RawCategoryNode[];
}

async function main() {
  const response = await fetch(CATEGORIES_URL, {
    headers: {
      "User-Agent": "Mozilla/5.0",
      "X-DeviceOS": "0",
    },
  });

  if (!response.ok) {
    throw new Error(
      `generate-categories: ${CATEGORIES_URL} responded ${response.status}`,
    );
  }

  const raw = (await response.json()) as RawCategoriesResponse;
  const categories = flattenCategories(raw.categories);

  const output = `// GENERATED FILE — do not edit by hand.
// Produced by scripts/generate-categories.ts from a live call to
// ${CATEGORIES_URL}. Re-run \`pnpm codegen:categories\` to refresh.
import type { Category } from "./types.js";

export const generatedCategories: Category[] = ${JSON.stringify(categories, null, 2)};
`;

  await writeFile(
    new URL("../src/categories/generated.ts", import.meta.url),
    output,
  );

  console.log(
    `generate-categories: wrote ${categories.length} categories to src/categories/generated.ts`,
  );
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
