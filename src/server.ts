import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

export function createServer(): McpServer {
  const server = new McpServer({
    name: "wallapop-mcp",
    version: "0.1.0",
  });

  // No tools registered yet (Phase 1 is scaffold-only) — advertise the
  // `tools` capability with an empty list so `tools/list` responds instead
  // of erroring, since McpServer only wires the handler once a tool exists.
  server.server.registerCapabilities({ tools: { listChanged: true } });
  server.server.setRequestHandler(ListToolsRequestSchema, () => ({
    tools: [],
  }));

  return server;
}
