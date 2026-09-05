import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { createRegentsMcpServer } from "./server.js";

export async function runRegentsMcpStdio(configPath?: string): Promise<void> {
  const { server, close } = await createRegentsMcpServer({
    configPath,
    mode: "local-stdio",
  });
  const transport = new StdioServerTransport();

  const shutdown = async () => {
    await close();
  };

  process.once("SIGINT", () => {
    void shutdown();
  });
  process.once("SIGTERM", () => {
    void shutdown();
  });

  await server.connect(transport);
}
