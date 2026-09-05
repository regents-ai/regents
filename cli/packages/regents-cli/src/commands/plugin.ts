import { CliUsageError } from "../cli-usage-error.js";
import { getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";
import {
  installPlugin,
  installableRuntimes,
  pluginStatus,
  selectedRuntimes,
  type RegentAgentRuntimeSelector,
} from "../internal-runtime/plugin-bridge.js";

const parseRuntimeSelector = (value: string | undefined): RegentAgentRuntimeSelector => {
  const runtime = value ?? "auto";
  if (runtime === "auto" || runtime === "hermes" || runtime === "openclaw") {
    return runtime;
  }
  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--runtime must be auto, hermes, or openclaw.",
  });
};

const withRuntimeFlag = (command: string, runtime: RegentAgentRuntimeSelector): string =>
  runtime === "auto" ? command : `${command} --runtime ${runtime}`;

export async function runPluginStatus(args: ParsedCliArgs): Promise<number> {
  const report = pluginStatus(parseRuntimeSelector(getFlag(args, "runtime")));
  const missing = report.runtimes.filter((runtime) => !runtime.installed);

  printJson({
    ...report,
    next_steps: missing.length > 0
      ? [withRuntimeFlag("regents plugin install", report.selectedRuntime)]
      : ["regents run"],
  });
  return 0;
}

export async function runPluginInstall(args: ParsedCliArgs): Promise<number> {
  const runtime = parseRuntimeSelector(getFlag(args, "runtime"));
  // "auto" installs only for runtimes that actually exist on this machine; an
  // explicit --runtime always installs for that runtime.
  const runtimes = installableRuntimes(runtime);
  const skipped = selectedRuntimes(runtime).filter((entry) => !runtimes.includes(entry));
  const includesHermes = runtimes.includes("hermes");

  printJson({
    ok: true,
    selectedRuntime: runtime,
    installed_plugins: runtimes.map((entry) => installPlugin(entry)),
    skipped_runtimes: skipped,
    next_steps: [
      ...(runtimes.length === 0
        ? ["Install Hermes or OpenClaw, then re-run: regents plugin install"]
        : []),
      ...(includesHermes ? ["hermes auth add xai-oauth"] : []),
      withRuntimeFlag("regents plugin doctor", runtime),
      "regents run",
    ],
  });
  return 0;
}

export async function runPluginDoctor(args: ParsedCliArgs): Promise<number> {
  const report = pluginStatus(parseRuntimeSelector(getFlag(args, "runtime")));
  const missing = report.runtimes.filter((runtime) => !runtime.installed).map((runtime) => runtime.runtime);
  printJson({
    ...report,
    ok: missing.length === 0,
    missing,
    next_steps: missing.length > 0
      ? [withRuntimeFlag("regents plugin install", report.selectedRuntime)]
      : ["regents run"],
  });
  return 0;
}
