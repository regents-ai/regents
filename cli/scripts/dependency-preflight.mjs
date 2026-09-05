import { existsSync } from "node:fs";
import { resolve } from "node:path";

export function assertWorkspaceDependencies(root) {
  if (existsSync(resolve(root, "node_modules/yaml"))) {
    return;
  }

  console.error(
    [
      "Regents CLI contract checks need workspace dependencies.",
      "Run: corepack enable && pnpm install --frozen-lockfile",
    ].join("\n"),
  );
  process.exit(1);
}

export async function loadYaml(root) {
  assertWorkspaceDependencies(root);
  return (await import("yaml")).default;
}
