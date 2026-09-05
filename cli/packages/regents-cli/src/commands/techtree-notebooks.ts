import { CliUsageError } from "../cli-usage-error.js";
import { withNextSteps } from "../command-payload.js";
import { daemonCall } from "../daemon-client.js";
import { getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson } from "../printer.js";

const parseKind = (value: string | undefined): "paper" | "freeform" => {
  if (value === "paper" || value === "freeform") {
    return value;
  }

  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--kind must be paper or freeform.",
  });
};

export async function runTechtreeNotebooksInit(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const workspacePath = requireArg(getFlag(args, "workspace-path"), "--workspace-path");
  printJson(
    withNextSteps(await daemonCall(
      "techtree.notebooks.init",
      {
        workspace_path: workspacePath,
        kind: parseKind(getFlag(args, "kind")),
        title: requireArg(getFlag(args, "title"), "--title"),
        source: getFlag(args, "source"),
      },
      configPath,
    ), [`regents techtree notebooks pair --workspace-path ${workspacePath}`]),
  );
}

export async function runTechtreeNotebooksPair(args: ParsedCliArgs, configPath?: string): Promise<void> {
  const workspacePath = requireArg(getFlag(args, "workspace-path"), "--workspace-path");
  printJson(
    withNextSteps(await daemonCall(
      "techtree.notebooks.pair",
      {
        workspace_path: workspacePath,
      },
      configPath,
    ), []),
  );
}
