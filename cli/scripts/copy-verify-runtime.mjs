import { cpSync, mkdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const source = path.join(repoRoot, "packages", "verify-runtime");
const target = path.join(repoRoot, "packages", "regents-cli", "dist", "verify-runtime");

rmSync(target, { recursive: true, force: true });
mkdirSync(target, { recursive: true });

for (const entry of ["pyproject.toml", "uv.lock", "verify_runtime"]) {
  cpSync(path.join(source, entry), path.join(target, entry), { recursive: true });
}
