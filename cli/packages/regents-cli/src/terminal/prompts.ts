import readline from "node:readline/promises";

import { CliUsageError } from "../cli-usage-error.js";
import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";

interface PromptOptions {
  readonly allowEmpty?: boolean;
  readonly fallback?: string;
  readonly unavailableMessage: string;
}

interface ChoiceOptions {
  readonly unavailableMessage: string;
}

interface ConfirmOptions {
  readonly unavailableMessage: string;
}

export interface PromptBoundary {
  readonly inputAllowed: boolean;
  text(label: string, options: PromptOptions): Promise<string>;
  choice(label: string, options: readonly string[], promptOptions: ChoiceOptions): Promise<number>;
  confirm(message: string, options: ConfirmOptions): Promise<boolean>;
}

export const promptInputAllowed = (args: ParsedCliArgs): boolean =>
  Boolean(process.stdout.isTTY) &&
  Boolean(process.stdin.isTTY) &&
  !getBooleanFlag(args, "no-input");

const assertInputAllowed = (allowed: boolean, message: string): void => {
  if (!allowed) {
    throw new CliUsageError({
      code: "input_required",
      message,
    });
  }
};

export const createPromptBoundary = (args: ParsedCliArgs): PromptBoundary => {
  const inputAllowed = promptInputAllowed(args);

  return {
    inputAllowed,
    async text(label, options) {
      assertInputAllowed(inputAllowed, options.unavailableMessage);
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });

      try {
        while (true) {
          const suffix = options.fallback ? ` [${options.fallback}]` : "";
          const answer = (await rl.question(`${label}${suffix}: `)).trim();
          const resolved = answer || options.fallback || "";
          if (options.allowEmpty || resolved !== "") {
            return resolved;
          }
        }
      } finally {
        rl.close();
      }
    },

    async choice(label, options, promptOptions) {
      assertInputAllowed(inputAllowed, promptOptions.unavailableMessage);
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });

      try {
        const rendered = options
          .map((option, index) => `${index + 1}. ${option}`)
          .join("\n");
        while (true) {
          const answer = (await rl.question(`${label}\n${rendered}\nChoose [1-${options.length}]: `)).trim();
          const parsed = Number.parseInt(answer, 10);
          if (Number.isSafeInteger(parsed) && parsed >= 1 && parsed <= options.length) {
            return parsed - 1;
          }
        }
      } finally {
        rl.close();
      }
    },

    async confirm(message, options) {
      assertInputAllowed(inputAllowed, options.unavailableMessage);
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });

      try {
        const answer = (await rl.question(`${message} [y/N] `)).trim().toLowerCase();
        return answer === "y" || answer === "yes";
      } finally {
        rl.close();
      }
    },
  };
};
