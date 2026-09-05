import { createRequire } from "node:module";

import { CLI_PALETTE, isHumanTerminal, tone } from "./palette.js";

const requireFromModule = createRequire(import.meta.url);

const PIXEL_LETTERS: readonly (readonly string[])[] = [
  // R
  ["██████ ", "██   ██", "██████ ", "██   ██", "██   ██"],
  // E
  ["███████", "██     ", "█████  ", "██     ", "███████"],
  // G
  [" ██████ ", "██      ", "██   ███", "██    ██", " ██████ "],
  // E
  ["███████", "██     ", "█████  ", "██     ", "███████"],
  // N
  ["███    ██", "████   ██", "██ ██  ██", "██  ██ ██", "██   ████"],
  // T
  ["████████", "   ██   ", "   ██   ", "   ██   ", "   ██   "],
  // S
  ["███████", "██     ", "███████", "     ██", "███████"],
] as const;

const LOGO_ROWS: readonly string[] = [0, 1, 2, 3, 4].map((row) =>
  PIXEL_LETTERS.map((letter) => letter[row]).join(" "),
);

const LOGO_WIDTH = LOGO_ROWS[0]?.length ?? 0;

export const cliVersion = (): string => {
  try {
    const pkg = requireFromModule("../../package.json") as { version?: string };
    return typeof pkg.version === "string" ? pkg.version : "";
  } catch {
    return "";
  }
};

export const renderBanner = (): string => {
  if (!isHumanTerminal()) {
    return "";
  }

  const version = cliVersion();
  const tagline = `work with Regent from the terminal${version ? `   v${version}` : ""}`;
  const columns = typeof process.stdout.columns === "number" ? process.stdout.columns : 100;

  if (columns < LOGO_WIDTH + 2) {
    return `${tone("◆ REGENTS", CLI_PALETTE.accent, true)}${version ? ` ${tone(`v${version}`, CLI_PALETTE.secondary)}` : ""}`;
  }

  return [
    ...LOGO_ROWS.map((row) => tone(row, CLI_PALETTE.accent)),
    "",
    tone(tagline, CLI_PALETTE.secondary),
  ].join("\n");
};
