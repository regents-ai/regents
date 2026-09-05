import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";
import { printJson } from "./json.js";
import { CLI_PALETTE, isHumanTerminal, tone } from "./palette.js";
import { renderPanel } from "./panel.js";
import { printText, renderKeyValuePanel, type KeyValueRow } from "./presenters.js";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const display = (value: unknown): string | undefined => {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }

  return typeof value === "string" ? value : JSON.stringify(value);
};

const shortHex = (value: unknown): string | undefined => {
  if (typeof value !== "string") {
    return undefined;
  }

  if (!value.startsWith("0x") || value.length <= 18) {
    return value;
  }

  return `${value.slice(0, 10)}...${value.slice(-6)}`;
};

const dataSelector = (value: unknown): string | undefined =>
  typeof value === "string" && value.startsWith("0x") && value.length >= 10
    ? value.slice(0, 10)
    : undefined;

export const preparedWalletActionFromEnvelope = (
  envelope: Record<string, unknown>,
  missingMessage = "This action did not include a transaction to submit.",
): Record<string, unknown> => {
  const prepared = envelope.prepared;
  if (!isRecord(prepared)) {
    throw new Error(missingMessage);
  }

  return prepared;
};

const walletActionFromPrepared = (prepared: Record<string, unknown>): Record<string, unknown> =>
  isRecord(prepared.wallet_action) ? prepared.wallet_action : prepared;

export const renderPreparedWalletAction = (
  prepared: Record<string, unknown>,
  options?: { title?: string; submitHint?: string },
): string => {
  const action = walletActionFromPrepared(prepared);
  const rows: KeyValueRow[] = [
    { label: "action", value: display(action.action ?? prepared.action) ?? "prepared" },
    { label: "resource", value: display(action.resource ?? prepared.resource) ?? "action" },
    { label: "id", value: display(action.resource_id ?? prepared.resource_id) ?? "pending" },
    { label: "signer", value: shortHex(action.expected_signer ?? prepared.expected_signer) ?? "current wallet" },
    { label: "chain", value: display(action.chain_id ?? prepared.chain_id) ?? "configured" },
    { label: "target", value: shortHex(action.to) ?? "contract" },
    { label: "value", value: display(action.value) ?? "0" },
    { label: "selector", value: dataSelector(action.data) ?? "none" },
    { label: "expires", value: display(action.expires_at ?? prepared.expires_at) ?? "not set" },
  ];
  const summary = renderKeyValuePanel(options?.title ?? "WALLET ACTION", rows, {
    borderColor: CLI_PALETTE.chrome,
    titleColor: CLI_PALETTE.title,
  });
  const next = renderPanel(
    "NEXT",
    [
      "Review this request before submitting.",
      options?.submitHint ?? "Run the same command with --submit when ready.",
    ],
    {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    },
  );

  return [
    summary,
    renderPanel("NOTE", [
      tone("Nothing changes until the transaction is submitted and confirmed.", CLI_PALETTE.secondary),
    ]),
    next,
  ].join("\n\n");
};

export const printWalletActionEnvelope = (
  args: ParsedCliArgs,
  envelope: Record<string, unknown>,
  options?: { title?: string; submitHint?: string; missingMessage?: string },
): void => {
  if (isHumanTerminal() && !getBooleanFlag(args, "json")) {
    printText(
      renderPreparedWalletAction(
        preparedWalletActionFromEnvelope(envelope, options?.missingMessage),
        options,
      ),
    );
    return;
  }

  printJson(envelope);
};
