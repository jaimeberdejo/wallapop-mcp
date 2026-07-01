# Phase 1 — Project scaffold & MCP server skeleton

## Research notes
- `@modelcontextprotocol/sdk` (latest 1.29.0) provides `McpServer` + `StdioServerTransport`
  for a stdio-transport MCP server. A server with zero registered tools still answers
  `tools/list` with an empty array — satisfies "empty/placeholder tool set" without inventing
  scope not yet in the roadmap.
- pnpm/corepack were not preinstalled in this environment; installed pnpm globally via
  `npm install -g pnpm` (tooling prerequisite, not a repo change).
- Toolchain versions resolved at plan time: typescript ^6.0, tsup ^8.5, vitest ^4.1,
  eslint ^10.6 (flat config) + typescript-eslint ^8.6, prettier ^3.9, eslint-config-prettier ^10.1.
- ESM throughout (`"type": "module"`), Node's built-in test runner not used — Vitest per spec.

## Tasks
1. `package.json` + `pnpm-lock.yaml` — deps, scripts (`build`, `test`, `typecheck`, `lint`,
   `format`, `start`), `"type": "module"`.
2. `tsconfig.json` — strict, ESM/NodeNext resolution, target a current Node LTS.
3. `tsup.config.ts` — bundles `src/index.ts` → `dist/index.js`, single file, ESM, shebang for CLI use later.
4. `vitest.config.ts` — node environment.
5. ESLint flat config (`eslint.config.js`) + Prettier config (`.prettierrc`), wired to `pnpm lint` / `pnpm format`.
6. `src/server.ts` — `createServer()` factory returning a configured `McpServer` (no tools registered yet).
7. `src/index.ts` — CLI entry: creates the server, connects a `StdioServerTransport`.
8. `tests/server.test.ts` — failing-first: asserts `createServer()` returns a server whose
   `tools/list` responds with an empty tools array (in-process, via the SDK's in-memory transport
   pair, not the built CLI — keeps the test fast and independent of the stdio process).

## Done when
`pnpm build && pnpm test && pnpm typecheck && pnpm lint` all pass, and a manual `tools/list`
call against the built stdio server returns a response (no tools required yet).
