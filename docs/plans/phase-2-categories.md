# Phase 2 — Category tree codegen & `list_categories` tool

## Research notes
- Verified the live shape by calling `api/v3/categories` directly from a Node script (curl/wget
  are denied in `.claude/settings.json`; `fetch()` from Node is not, and is what the codegen
  script needs to use at runtime anyway):
  - Top-level shape: `{ "categories": [...] }`, 18 top-level entries, 997 nodes total, max
    nesting depth 5.
  - Each node has `id` (number), `name` (string), `subcategories` (array, recursive). Non-root
    nodes also have `parent_id`; the raw `path` field is only the **immediate parent's name**,
    not the full ancestor chain — so "path to its ancestors" (per `CONTEXT.md`'s `Category`
    definition) must be built ourselves by walking the tree, not read off the raw field.
  - Root nodes additionally carry `vertical_id`, `icon`, `category_leaf_selection_mandatory`,
    and richer `presentation`/`attributes` — all Wallapop-presentation fields, out of scope per
    the `Category` language entry (id, name, path to ancestors only).
- `Category` (from `CONTEXT.md`): id, name, path to ancestors. Modeled as
  `{ id: number; name: string; path: string[] }` where `path` is ancestor names, root-first,
  excluding the node itself (`[]` for a top-level category).

## Tasks
1. `src/categories/types.ts` — `Category` type.
2. `src/categories/flatten.ts` — pure `flattenCategories(tree)` walking the raw nested shape
   into a flat `Category[]`, computing each node's ancestor `path` itself.
3. `src/categories/search.ts` — pure `searchCategories(categories, query?)`: no query → only
   top-level categories (`path.length === 0`); query → case-insensitive substring match on `name`
   across all depths.
4. `scripts/generate-categories.ts` — one-off codegen: `fetch()`s `api/v3/categories` live,
   runs `flattenCategories`, writes `src/categories/generated.ts` (a static `Category[]` const).
   Run once by hand now to produce the checked-in file (not part of `pnpm build`/`pnpm test`).
5. `src/server.ts` — register the `list_categories` tool, wired to
   `searchCategories(generatedCategories, query)`.
6. Tests (Vitest, no live network calls):
   - `tests/categories/flatten.test.ts` — fixture raw tree → expected flat `Category[]`
     (checks ancestor path construction, not just direct-parent).
   - `tests/categories/search.test.ts` — fixture flat list → no-query returns only top-level;
     query matches by substring, case-insensitively, across depths.
   - `tests/server.test.ts` (extend) — `list_categories` tool call with no query, against the
     REAL generated `src/categories/generated.ts`, returns exactly its top-level categories.

## Done when
`pnpm test` passes for category flatten/search logic, and calling `list_categories` with no
query returns exactly the top-level categories from the generated static file.
