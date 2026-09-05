import { CLI_COMMANDS } from "./generated/cli-command-metadata.js";

export { CLI_COMMANDS };

export type CliCommandName = (typeof CLI_COMMANDS)[number];

export const cliCommandSet = new Set<string>(CLI_COMMANDS);

export const commandMatchesInput = (command: string, input: readonly string[]): boolean => {
  const commandParts = command.split(" ");
  if (commandParts.length !== input.length) {
    return false;
  }

  return commandParts.every((part, index) => part.startsWith("<") && part.endsWith(">") ? Boolean(input[index]) : part === input[index]);
};

export const knownCliCommand = (input: readonly string[]): boolean =>
  CLI_COMMANDS.some((command) => commandMatchesInput(command, input));
