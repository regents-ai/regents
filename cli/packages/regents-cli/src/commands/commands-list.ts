import {
  CLI_COMMAND_DETAILS_BY_COMMAND,
  CLI_COMMANDS,
} from "../generated/cli-command-metadata.js";
import { getBooleanFlag, getFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText } from "../printer.js";

interface CommandIndexEntry {
  command: string;
  summary?: string;
}

const commandDetails = CLI_COMMAND_DETAILS_BY_COMMAND as Readonly<
  Record<string, CommandIndexEntry | undefined>
>;

const matchesSearch = (command: string, search: string): boolean => {
  const needle = search.toLowerCase();
  if (command.toLowerCase().includes(needle)) {
    return true;
  }

  const summary = commandDetails[command]?.summary;
  return typeof summary === "string" && summary.toLowerCase().includes(needle);
};

export async function runCommandsList(args: ParsedCliArgs): Promise<number> {
  const search = getFlag(args, "search");
  const commands = search
    ? CLI_COMMANDS.filter((command) => matchesSearch(command, search))
    : [...CLI_COMMANDS];

  if (getBooleanFlag(args, "json")) {
    printJson({
      ok: true,
      total: commands.length,
      ...(search ? { search } : {}),
      commands: commands.map((command) => commandDetails[command] ?? { command }),
    });
    return 0;
  }

  for (const command of commands) {
    const summary = commandDetails[command]?.summary;
    printText(summary ? `regents ${command} - ${summary}` : `regents ${command}`);
  }

  printText(
    search
      ? `${commands.length} commands match "${search}". Run with --json for full command details.`
      : `${commands.length} commands. Run with --json for full command details.`,
  );
  return 0;
}
