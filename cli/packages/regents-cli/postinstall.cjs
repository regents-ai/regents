#!/usr/bin/env node

if (process.env.npm_config_loglevel === "silent") {
  process.exit(0);
}

const { version } = require("./package.json");

const gold = "\x1b[38;2;212;167;86m";
const ivory = "\x1b[38;2;251;244;222m";
const grey = "\x1b[38;2;132;128;120m";
const bold = "\x1b[1m";
const reset = "\x1b[0m";

const colorAllowed =
  process.env.NO_COLOR === undefined &&
  process.env.npm_config_color !== "false" &&
  process.env.TERM !== "dumb";
const isTty = Boolean(process.stdout.isTTY);

const paint = (text, color, emphasize = false) =>
  colorAllowed && isTty ? `${emphasize ? bold : ""}${color}${text}${reset}` : text;

const logoRows = [
  "██████  ███████  ██████  ███████ ███    ██ ████████ ███████",
  "██   ██ ██      ██       ██      ████   ██    ██    ██     ",
  "██████  █████   ██   ███ █████   ██ ██  ██    ██    ███████",
  "██   ██ ██      ██    ██ ██      ██  ██ ██    ██         ██",
  "██   ██ ███████  ██████  ███████ ██   ████    ██    ███████",
];

const logoFits =
  isTty && (typeof process.stdout.columns !== "number" || process.stdout.columns >= logoRows[0].length + 2);

const alphaWarning =
  "Regents apps and the CLI are in ALPHA testing and funds are not guaranteed safe in any shape or form";

const startRows = [
  ["regents init", "guided setup and a readiness check"],
  ["regents setup skills", "install the Regents agent skills"],
  ["regents status", "see what is ready"],
];
const commandWidth = Math.max(...startRows.map(([command]) => command.length));

process.stdout.write(
  [
    "",
    ...(logoFits ? [...logoRows.map((row) => paint(row, gold)), ""] : []),
    paint(`Regents CLI v${version} is installed.`, ivory, true),
    paint(alphaWarning, gold, true),
    "",
    `${paint("Start here:", grey, true)}  ${paint("run", grey)} ${paint("regents init", ivory, true)} ${paint("for guided setup.", grey)}`,
    "",
    paint("Or pick a command:", grey, true),
    ...startRows.map(
      ([command, description]) =>
        `  ${paint(command.padEnd(commandWidth), ivory, true)}  ${paint(description, grey)}`,
    ),
    "",
    paint("Already installed? You are on the latest. Run `regents` to see what is ready.", grey),
    "",
  ].join("\n"),
);
