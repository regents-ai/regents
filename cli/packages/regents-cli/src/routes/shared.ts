import { CLI_COMMANDS } from "../command-registry.js";
import type { ParsedCliArgs } from "../parse.js";

export type CliRouteContext = {
  rawArgs: string[];
  parsedArgs: ParsedCliArgs;
  configPath: string | undefined;
  positionals: readonly string[];
};

export type CliRouteHandler = (context: CliRouteContext) => Promise<number>;

export type CliRoute = {
  command: string;
  pattern: readonly string[];
  variadicTail: boolean;
  handler: CliRouteHandler;
};

export const route = (
  command: string,
  handler: CliRouteHandler,
  options?: { readonly variadicTail?: boolean; readonly pattern?: string },
): CliRoute => ({
  command,
  pattern: (options?.pattern ?? command).split(" "),
  variadicTail: options?.variadicTail ?? false,
  handler,
});

/**
 * A declarative handler-registry entry. `run` is a plain reference to the
 * command handler (it may return void for the common case or a number when the
 * command owns its own exit code). `variadicTail`/`pattern` mirror the matching
 * options accepted by `route()`.
 */
export type CliHandlerEntry = {
  readonly run: (context: CliRouteContext) => number | void | Promise<number | void>;
  readonly variadicTail?: boolean;
  readonly pattern?: string;
};

export type CliHandlerRegistry = Readonly<Record<string, CliHandlerEntry>>;

/**
 * Build the route table by iterating the generated command metadata. For every
 * command name in `commands`, the matching registry entry supplies the handler
 * plus its variadicTail/pattern matching behaviour. A uniform wrapper subsumes
 * the void-vs-number return split: void handlers resolve to exit code 0.
 *
 * Throws if a command has no registry handler (or a registry entry has no
 * command) so a coverage gap surfaces as a hard failure rather than a silently
 * unroutable command.
 */
export const buildRoutesFromRegistry = (
  commands: readonly string[],
  registry: CliHandlerRegistry,
): readonly CliRoute[] => {
  const missingHandlers = commands.filter((command) => registry[command] === undefined);
  const extraHandlers = Object.keys(registry).filter((command) => !commands.includes(command));
  if (missingHandlers.length > 0 || extraHandlers.length > 0) {
    throw new Error(
      [
        missingHandlers.length > 0
          ? `CLI commands missing registry handlers: ${missingHandlers.join(", ")}`
          : undefined,
        extraHandlers.length > 0
          ? `Registry handlers missing CLI commands: ${extraHandlers.join(", ")}`
          : undefined,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }

  return commands.map((command) => {
    const entry = registry[command];
    return route(
      command,
      async (context) => {
        const result = await entry.run(context);
        return typeof result === "number" ? result : 0;
      },
      { variadicTail: entry.variadicTail, pattern: entry.pattern },
    );
  });
};

const isPlaceholderPart = (part: string): boolean => part.startsWith("<") && part.endsWith(">");

const inputIsReservedLiteralCommandPrefix = (
  candidate: CliRoute,
  positionals: readonly string[],
): boolean =>
  CLI_COMMANDS.some((command) => {
    if (command === candidate.command) {
      return false;
    }

    const commandParts = command.split(" ");
    if (commandParts.length < positionals.length) {
      return false;
    }

    return positionals.every((part, index) => {
      const commandPart = commandParts[index];
      return commandPart !== undefined && !isPlaceholderPart(commandPart) && commandPart === part;
    });
  });

export const routeMatches = (candidate: CliRoute, positionals: readonly string[]): boolean => {
  if (candidate.pattern.length > positionals.length) {
    return false;
  }

  if (!candidate.variadicTail && candidate.pattern.length !== positionals.length) {
    return false;
  }

  return candidate.pattern.every((part, index) => {
    const input = positionals[index];
    if (!isPlaceholderPart(part)) {
      return part === input;
    }

    if (!input) {
      return false;
    }

    return !inputIsReservedLiteralCommandPrefix(candidate, positionals.slice(0, index + 1));
  });
};

export const dispatchRoute = async (
  routes: readonly CliRoute[],
  context: CliRouteContext,
): Promise<number | undefined> => {
  const matchedRoute = routes
    .filter((candidate) => routeMatches(candidate, context.positionals))
    .sort((left, right) => right.pattern.length - left.pattern.length)[0];
  return matchedRoute ? matchedRoute.handler(context) : undefined;
};

export const assertRouteRegistryMatches = (routes: readonly CliRoute[]): void => {
  const routeCommands = routes.map((candidate) => candidate.command).sort();
  const registryCommands = [...CLI_COMMANDS].sort();
  const routeCommandSet = new Set(routeCommands);
  const routeCommandsWithoutPlaceholders = new Set(
    routeCommands.map((command) =>
      command
        .split(" ")
        .filter((part) => !isPlaceholderPart(part))
        .join(" "),
    ),
  );
  const registryCommandSet = new Set<string>(registryCommands);
  const missingRoutes = registryCommands.filter(
    (command) => !routeCommandSet.has(command) && !routeCommandsWithoutPlaceholders.has(command),
  );
  const missingRegistryEntries = routeCommands.filter((command) => {
    const commandWithoutPlaceholders = command
      .split(" ")
      .filter((part) => !isPlaceholderPart(part))
      .join(" ");
    return !registryCommandSet.has(command) && !registryCommandSet.has(commandWithoutPlaceholders);
  });

  if (missingRoutes.length > 0 || missingRegistryEntries.length > 0) {
    throw new Error(
      [
        missingRoutes.length > 0 ? `CLI registry commands missing routes: ${missingRoutes.join(", ")}` : undefined,
        missingRegistryEntries.length > 0
          ? `CLI routes missing registry commands: ${missingRegistryEntries.join(", ")}`
          : undefined,
      ]
        .filter(Boolean)
        .join("\n"),
    );
  }
};
