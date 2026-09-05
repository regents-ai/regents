import fs from "node:fs";
import { resolve } from "node:path";

const binding = resolve(import.meta.dirname, "../packages/regents-cli/src/generated/autolaunch-openapi.ts");
const source = fs.readFileSync(binding, "utf8");
if (!source.includes("export interface paths") || !/^    "\/api\/autolaunch\//mu.test(source)) {
  console.error(`Autolaunch copied API binding is invalid: ${binding}`);
  process.exit(1);
}
console.log("Autolaunch copied API binding check passed");
