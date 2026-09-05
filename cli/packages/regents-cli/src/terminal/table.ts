import { renderPanel } from "./panel.js";
import { alignCell, CLI_PALETTE, escapeTerminalText, tone } from "./palette.js";

export interface TableColumn {
  header: string;
  align?: "left" | "right" | "center";
  color?: string;
  minWidth?: number;
  maxWidth?: number;
}

export interface TableRow {
  cells: readonly string[];
  colors?: readonly (string | undefined)[];
}

const MIN_CONTENT_WIDTH = 24;
const PANEL_CHROME_WIDTH = 4;
const MIN_CELL_WIDTH = 3;
const CELL_SEPARATOR_WIDTH = 3;

const terminalContentWidth = (): number => {
  const columns = typeof process.stdout.columns === "number" ? process.stdout.columns : 100;
  return Math.max(MIN_CONTENT_WIDTH, columns - PANEL_CHROME_WIDTH);
};

const totalWidth = (widths: readonly number[]): number =>
  widths.reduce((sum, width) => sum + width, 0) + Math.max(0, widths.length - 1) * CELL_SEPARATOR_WIDTH;

const shrinkWidths = (
  naturalWidths: readonly number[],
  minWidths: readonly number[],
  maxWidth: number,
): number[] => {
  const widths = [...naturalWidths];

  while (totalWidth(widths) > maxWidth) {
    const shrinkIndex = widths.reduce((bestIndex, width, index) => {
      const bestRoom = widths[bestIndex] - minWidths[bestIndex];
      const room = width - minWidths[index];
      return room > bestRoom ? index : bestIndex;
    }, 0);

    if (widths[shrinkIndex] <= minWidths[shrinkIndex]) {
      break;
    }

    widths[shrinkIndex] -= 1;
  }

  return widths;
};

const truncateCell = (value: string, width: number): string => {
  if (value.length <= width) {
    return value;
  }

  if (width <= 3) {
    return value.slice(0, width);
  }

  return `${value.slice(0, width - 3)}...`;
};

export const renderTablePanel = (
  title: string,
  columns: readonly TableColumn[],
  rows: readonly TableRow[],
  options?: { borderColor?: string; titleColor?: string },
): string => {
  const safeColumns = columns.map((column) => ({
    ...column,
    header: escapeTerminalText(column.header),
  }));
  const safeRows = rows.map((row) => ({
    ...row,
    cells: row.cells.map(escapeTerminalText),
  }));
  const naturalWidths = safeColumns.map((column, index) => {
    const headerWidth = column.header.length;
    const rowWidths = safeRows.map((row) => (row.cells[index] ?? "").length);
    const naturalWidth = Math.max(column.minWidth ?? 0, headerWidth, ...rowWidths, MIN_CELL_WIDTH);
    return column.maxWidth === undefined ? naturalWidth : Math.min(naturalWidth, column.maxWidth);
  });
  const targetWidth = terminalContentWidth();
  const requestedMinWidths = safeColumns.map((column, index) =>
    Math.max(
      MIN_CELL_WIDTH,
      Math.min(column.minWidth ?? MIN_CELL_WIDTH, naturalWidths[index] ?? MIN_CELL_WIDTH),
    ),
  );
  const minWidths = totalWidth(requestedMinWidths) > targetWidth
    ? safeColumns.map(() => MIN_CELL_WIDTH)
    : requestedMinWidths;
  const widths = shrinkWidths(naturalWidths, minWidths, targetWidth);

  const header = safeColumns
    .map((column, index) => {
      const width = widths[index] ?? MIN_CELL_WIDTH;
      return alignCell(
        tone(truncateCell(column.header, width), column.color ?? CLI_PALETTE.title, true),
        width,
        column.align,
      );
    })
    .join(" │ ");
  const separator = widths.map((width) => "─".repeat(width)).join("─┼─");
  const body = safeRows.map((row) =>
    safeColumns
      .map((column, index) => {
        const cell = row.cells[index] ?? "";
        const width = widths[index] ?? MIN_CELL_WIDTH;
        const cellColor = row.colors?.[index] ?? column.color ?? CLI_PALETTE.primary;
        return alignCell(tone(truncateCell(cell, width), cellColor), width, column.align);
      })
      .join(" │ "),
  );

  return renderPanel(title, [header, separator, ...body], options);
};
