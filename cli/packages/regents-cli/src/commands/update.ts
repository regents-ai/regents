import { spawnSync } from "node:child_process";

import type { ParsedCliArgs } from "../parse.js";

import { getBooleanFlag, getFlag } from "../parse.js";
import { cliVersion, printJson, printText } from "../printer.js";

const PACKAGE_NAME = "@regentslabs/cli";

const fetchLatestVersion = (): { version?: string; error?: string } => {
  const result = spawnSync("npm", ["view", PACKAGE_NAME, "version"], {
    stdio: "pipe",
    encoding: "utf8",
    timeout: 60_000,
  });

  if (result.status !== 0 || result.error) {
    return {
      error: result.error?.message ?? (`${result.stderr ?? ""}`.trim() || "npm view failed"),
    };
  }

  const version = `${result.stdout ?? ""}`.trim();
  return version ? { version } : { error: "npm view returned no version" };
};

const runUpdateCheck = (wantsJson: boolean): number => {
  const installed = cliVersion() || "unknown";
  const { version: latest, error } = fetchLatestVersion();

  if (!latest) {
    if (wantsJson) {
      printJson({
        ok: false,
        check: true,
        installed_version: installed,
        latest_version: null,
        up_to_date: null,
        detail: `The latest published version could not be read: ${error}`,
        next: ["regents update --check"],
      });
    } else {
      printText(`Installed version: ${installed}. The latest published version could not be read: ${error}`);
    }
    return 1;
  }

  const upToDate = installed === latest;

  if (wantsJson) {
    printJson({
      ok: true,
      check: true,
      installed_version: installed,
      latest_version: latest,
      up_to_date: upToDate,
      detail: upToDate
        ? `Regents CLI ${installed} is the latest published release.`
        : `Regents CLI ${installed} is installed; ${latest} is the latest published release.`,
      next: upToDate ? [] : ["regents update"],
    });
    return 0;
  }

  if (upToDate) {
    printText(`Regents CLI ${installed} is the latest published release.`);
  } else {
    printText(`Regents CLI ${installed} is installed; ${latest} is available. Run 'regents update' to install it.`);
  }
  return 0;
};

export async function runUpdate(args: ParsedCliArgs): Promise<number> {
  const wantsJson = getBooleanFlag(args, "json");

  if (getBooleanFlag(args, "check")) {
    return runUpdateCheck(wantsJson);
  }

  const target = getFlag(args, "version") ?? "latest";
  const spec = `${PACKAGE_NAME}@${target}`;
  const before = cliVersion() || "unknown";

  if (!wantsJson) {
    printText(`Updating ${spec} (current: ${before})...`);
  }

  const result = spawnSync("npm", ["install", "-g", spec], {
    stdio: wantsJson ? "pipe" : "inherit",
    encoding: "utf8",
    timeout: 300_000,
  });

  const ok = result.status === 0 && !result.error;

  if (wantsJson) {
    printJson({
      ok,
      target,
      previous_version: before,
      detail: ok
        ? `Installed ${spec}.`
        : (result.error?.message ?? `${result.stderr ?? ""}`.trim() ?? "npm install failed"),
      next: ok ? ["regents setup --quick", "regents doctor"] : ["npm install -g " + spec],
    });
    return ok ? 0 : 1;
  }

  if (ok) {
    printText(`Updated. Run 'regents setup --quick' to refresh plugins, and 'regents doctor' to verify.`);
    return 0;
  }

  printText(`Update failed. Try running it directly: npm install -g ${spec}`);
  return 1;
}
