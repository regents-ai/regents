import { renderPanel } from "./panel.js";
import { alignCell, CLI_PALETTE, escapeTerminalText, stripAnsi, tone } from "./palette.js";
import { renderTablePanel } from "./table.js";

export interface KeyValueRow {
  label: string;
  value: string;
  labelColor?: string;
  valueColor?: string;
}

export const renderKeyValueLines = (rows: readonly KeyValueRow[]): string[] => {
  const safeRows = rows.map((row) => ({
    ...row,
    label: escapeTerminalText(row.label),
    value: escapeTerminalText(row.value),
  }));
  const labelWidth = safeRows.reduce((max, row) => Math.max(max, stripAnsi(row.label).length), 0);
  return safeRows.map((row) => {
    const label = tone(row.label, row.labelColor ?? CLI_PALETTE.secondary, true);
    const value = tone(row.value, row.valueColor ?? CLI_PALETTE.primary, row.valueColor === CLI_PALETTE.error);
    return `${alignCell(label, labelWidth, "right")}  ${value}`;
  });
};

export const renderKeyValuePanel = (
  title: string,
  rows: readonly KeyValueRow[],
  options?: { borderColor?: string; titleColor?: string },
): string => renderPanel(title, renderKeyValueLines(rows), options);

export function renderUsageScreen(configPath: string): string {
  const lines = [
    tone("direct control surface for Regent operators and agents", CLI_PALETTE.secondary),
    `${tone("default config", CLI_PALETTE.secondary)} ${tone(escapeTerminalText(configPath), CLI_PALETTE.primary, true)}`,
    "",
    tone("start simple", CLI_PALETTE.accent, true),
    "Use regents.sh for guided browser setup.",
    "Use this CLI for local identity, runtime, notebooks, and Autolaunch work.",
    "",
    tone("need a full command list?", CLI_PALETTE.secondary, true),
    "Run `regents help <product>` or `regents <command> --help`.",
  ];

  return [
    renderPanel("◆ R E G E N T   C L I", lines, {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderPanel("◆ START HERE", [
      "regents init",
      "regents status",
      "regents whoami",
      "regents run",
      "regents doctor",
    ]),
    renderPanel("◆ PRODUCT AREAS", [
      "regents platform auth login",
      "regents techtree notebooks init",
      "regents techtree notebooks pair",
      "regents autolaunch prelaunch wizard",
      "regents autolaunch launch run",
    ]),
    renderPanel("◆ TECHTREE NOTEBOOKS", [
      "regents techtree notebooks init --kind <paper|freeform> --title <title> --workspace-path <path>",
      "regents techtree notebooks pair --workspace-path <path>",
    ]),
    renderPanel("◆ COMMON NEXT STEPS", [
      "regents autolaunch safe wizard",
      "regents bug --summary \"can't do xyz\" --details \"any more details here\"",
      "regents security-report --summary \"private vuln\" --details \"steps and impact\" --contact \"@xyz on telegram\"",
    ]),
    tone("tip", CLI_PALETTE.secondary, true) + " add " + tone("--config /absolute/path.json", CLI_PALETTE.primary, true) + " to pin a non-default config.",
  ].join("\n\n");
}

export function printText(text: string): void {
  process.stdout.write(`${text}\n`);
}
