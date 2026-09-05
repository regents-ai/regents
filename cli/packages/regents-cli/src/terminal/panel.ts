import { ANSI, CLI_PALETTE, escapePresentationLine, escapeTerminalText, isHumanTerminal, padRight, stripAnsi, tone } from "./palette.js";

const BORDER = {
  topLeft: "╭",
  topRight: "╮",
  bottomLeft: "╰",
  bottomRight: "╯",
  horizontal: "─",
  vertical: "│",
} as const;

const MIN_CONTENT_WIDTH = 24;
const PANEL_CHROME_WIDTH = 4;

const terminalContentWidth = (): number => {
  const columns = typeof process.stdout.columns === "number" ? process.stdout.columns : 100;
  return Math.max(MIN_CONTENT_WIDTH, columns - PANEL_CHROME_WIDTH);
};

const splitLongWord = (word: string, width: number): string[] => {
  if (word.includes("\x1b") || stripAnsi(word).length <= width) {
    return [word];
  }

  const chunks: string[] = [];
  for (let index = 0; index < word.length; index += width) {
    chunks.push(word.slice(index, index + width));
  }
  return chunks;
};

const wrapLine = (line: string, width: number): string[] => {
  if (stripAnsi(line).length <= width) {
    return [line];
  }

  const words = line.match(/\S+/gu) ?? [];
  if (words.length === 0) {
    return [""];
  }

  const wrapped: string[] = [];
  let current = "";

  for (const wordPart of words.flatMap((word) => splitLongWord(word, width))) {
    if (current === "") {
      current = wordPart;
      continue;
    }

    const candidate = `${current} ${wordPart}`;
    if (stripAnsi(candidate).length <= width) {
      current = candidate;
      continue;
    }

    wrapped.push(current);
    current = wordPart;
  }

  if (current !== "") {
    wrapped.push(current);
  }

  return wrapped.length > 0 ? wrapped : [""];
};

export const renderPanel = (
  title: string,
  lines: string[],
  options?: { borderColor?: string; titleColor?: string },
): string => {
  const safeTitle = escapeTerminalText(title);
  const safeLines = lines.map(escapePresentationLine);
  if (!isHumanTerminal()) {
    return [safeTitle, ...safeLines].join("\n");
  }

  const maxContentWidth = terminalContentWidth();
  const wrappedLines = safeLines.flatMap((line) => wrapLine(line, maxContentWidth));
  const contentWidth = Math.min(
    maxContentWidth,
    Math.max(stripAnsi(safeTitle).length, ...wrappedLines.map((line) => stripAnsi(line).length), MIN_CONTENT_WIDTH),
  );
  const horizontal = BORDER.horizontal.repeat(contentWidth + 2);
  const borderColor = options?.borderColor ?? CLI_PALETTE.chrome;
  const titleColor = options?.titleColor ?? CLI_PALETTE.title;

  const titleTail = BORDER.horizontal.repeat(Math.max(0, contentWidth - stripAnsi(safeTitle).length - 1));
  const top = `${borderColor}${BORDER.topLeft}${BORDER.horizontal} ${tone(safeTitle, titleColor, true)} ${titleTail}${BORDER.topRight}${ANSI.reset}`;
  const body = wrappedLines.map((line) => `${borderColor}${BORDER.vertical}${ANSI.reset} ${padRight(line, contentWidth)} ${borderColor}${BORDER.vertical}${ANSI.reset}`);
  const bottom = `${borderColor}${BORDER.bottomLeft}${horizontal}${BORDER.bottomRight}${ANSI.reset}`;

  return [top, ...body, bottom].join("\n");
};
