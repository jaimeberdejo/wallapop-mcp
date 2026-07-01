# ADR-001: Advertise empty `tools/list` via the low-level `Server`, not a placeholder tool

Date: 2026-07-01
Decision: In `src/server.ts`, register the `tools` capability and a `ListToolsRequestSchema`
handler directly on `McpServer`'s underlying `server.server` (returning `{ tools: [] }`),
instead of calling `McpServer.registerTool()` with a no-op placeholder tool.
Why: `McpServer` only wires the `tools/list` handler once a tool is registered — with zero
tools it answers `Method not found`. A placeholder tool would satisfy `tools/list` but leak
fake capability into every client's tool listing, which the spec's Phase 1 scope (no tools yet)
explicitly doesn't want; the low-level `Server` API is documented as the SDK's supported escape
hatch for exactly this kind of custom handler.
