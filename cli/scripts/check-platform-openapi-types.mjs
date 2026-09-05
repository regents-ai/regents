import fs from "node:fs";
import { resolve } from "node:path";

const binding = resolve(import.meta.dirname, "../packages/regents-cli/src/generated/platform-openapi.ts");
const source = fs.readFileSync(binding, "utf8");
if (!source.includes("export interface paths") || !/^    "\//mu.test(source)) {
  console.error(`Platform copied API binding is invalid: ${binding}`);
  process.exit(1);
}
console.log("Platform copied API binding check passed");
