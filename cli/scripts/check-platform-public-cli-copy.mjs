import { checkCliCommandMetadata } from "./generate-cli-command-metadata.mjs";

const result = checkCliCommandMetadata();
if (!result.commandListOk) {
  console.error(`Public CLI command list is out of date: ${result.commandListPath}`);
  process.exit(1);
}
console.log("repository-local public CLI docs check passed");
