const rgb = (r: number, g: number, b: number): string => `\x1b[38;2;${r};${g};${b}m`;

export const ANSI = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  charcoalBlue: rgb(49, 85, 105),
  yaleBlue: rgb(3, 69, 104),
  ivoryMist: rgb(251, 244, 222),
  sunlitClay: rgb(212, 167, 86),
  greyOlive: rgb(132, 128, 120),
} as const;

export const CLI_PALETTE = {
  chrome: ANSI.charcoalBlue,
  title: ANSI.ivoryMist,
  accent: ANSI.sunlitClay,
  primary: ANSI.ivoryMist,
  secondary: ANSI.greyOlive,
  emphasis: ANSI.yaleBlue,
  error: ANSI.sunlitClay,
} as const;

const ANSI_PATTERN = /\x1b\[[0-9;]*m/g;
const CONTROL_CHARACTER_PATTERN = /[\u0000-\u0008\u000B\u000C\u000D-\u001F\u007F]/gu;

export const stripAnsi = (value: string): string => value.replace(ANSI_PATTERN, "");

export const isHumanTerminal = (): boolean =>
  Boolean(process.stdout.isTTY) && process.env.NO_COLOR === undefined && process.env.TERM !== "dumb";

export const tone = (value: string, color: string, bold = false): string => {
  if (!isHumanTerminal()) {
    return value;
  }

  const prefix = `${bold ? ANSI.bold : ""}${color}`;
  return `${prefix}${value}${ANSI.reset}`;
};

const escapeCharacter = (value: string): string => {
  const codePoint = value.codePointAt(0) ?? 0;
  if (codePoint === 0x7f) {
    return "\\x7f";
  }

  return `\\u${codePoint.toString(16).padStart(4, "0")}`;
};

export const escapeTerminalText = (value: string): string =>
  value.replace(CONTROL_CHARACTER_PATTERN, escapeCharacter);

export const escapePresentationLine = (value: string): string => {
  const markers: string[] = [];
  const protectedValue = value.replace(ANSI_PATTERN, (match) => {
    const index = markers.push(match) - 1;
    return `\uE000${index}\uE000`;
  });

  return escapeTerminalText(protectedValue).replace(/\uE000(\d+)\uE000/gu, (_match, index: string) => markers[Number(index)] ?? "");
};

export const padRight = (value: string, width: number): string => {
  const visible = stripAnsi(value).length;
  return visible >= width ? value : `${value}${" ".repeat(width - visible)}`;
};

export const padLeft = (value: string, width: number): string => {
  const visible = stripAnsi(value).length;
  return visible >= width ? value : `${" ".repeat(width - visible)}${value}`;
};

export const padCenter = (value: string, width: number): string => {
  const visible = stripAnsi(value).length;
  if (visible >= width) {
    return value;
  }

  const totalPadding = width - visible;
  const leftPadding = Math.floor(totalPadding / 2);
  const rightPadding = totalPadding - leftPadding;
  return `${" ".repeat(leftPadding)}${value}${" ".repeat(rightPadding)}`;
};

export const alignCell = (value: string, width: number, align: "left" | "right" | "center" = "left"): string => {
  if (align === "right") {
    return padLeft(value, width);
  }

  if (align === "center") {
    return padCenter(value, width);
  }

  return padRight(value, width);
};
