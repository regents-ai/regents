import {
  CLI_PALETTE,
  isHumanTerminal,
  printText,
  renderPanel,
} from "../../printer.js";

export const ALPHA_FUNDS_WARNING =
  "Regents apps and the CLI are in ALPHA testing and funds are not guaranteed safe in any shape or form";

export const printAlphaFundsWarning = (): void => {
  if (!isHumanTerminal()) {
    return;
  }

  printText(
    renderPanel("◆ ALPHA TESTING", [ALPHA_FUNDS_WARNING], {
      borderColor: CLI_PALETTE.error,
      titleColor: CLI_PALETTE.error,
    }),
  );
};
