import {
  CLI_PALETTE,
  isHumanTerminal,
  printText,
  renderPanel,
} from "../../printer.js";

const AGENT_SAFE_EXPLAINER_LINES = [
  "The Agent Safe is the shared control wallet for the launch.",
  "It protects the launch account, token setup, and post-launch ownership actions.",
  "Use a 2-of-3 Safe with the Agent signer, website wallet, and a backup signer.",
  "Keep the backup signer in a separate, well-protected wallet. A hardware wallet is best for mainnet.",
  "If you do not have one yet, run `regents autolaunch safe wizard`.",
] as const;

export const printAgentSafeExplainer = (): void => {
  if (!isHumanTerminal()) {
    return;
  }

  printText(
    renderPanel("◆ AGENT SAFE", [...AGENT_SAFE_EXPLAINER_LINES], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
  );
};
