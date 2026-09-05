import { CliUsageError } from "../cli-usage-error.js";
import { runAwalJson } from "../internal-runtime/agentic-wallet/awal.js";
import { getBooleanFlag, getFlag, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson, printText, renderKeyValuePanel } from "../printer.js";

const chain = (args: ParsedCliArgs): "base" => {
  const value = requireArg(getFlag(args, "chain"), "--chain");
  if (value === "base") {
    return value;
  }

  throw new CliUsageError({
    code: "unsupported_chain",
    message: "Agentic Wallet funding and balance checks currently use Base.",
    validValues: ["base"],
  });
};

const withNextSteps = (payload: unknown, nextSteps: readonly string[]): unknown => {
  if (payload && typeof payload === "object" && !Array.isArray(payload)) {
    return {
      ...(payload as Record<string, unknown>),
      next_steps: nextSteps,
    };
  }

  return { ok: true, data: payload, next_steps: nextSteps };
};

const printAwal = (args: ParsedCliArgs, payload: unknown, nextSteps: readonly string[]): void => {
  if (getBooleanFlag(args, "json")) {
    printJson(withNextSteps(payload, nextSteps));
    return;
  }

  printText(
    renderKeyValuePanel("◆ AGENTIC WALLET", [
      { label: "status", value: "ready" },
      { label: "details", value: "Use --json for the full Agentic Wallet response." },
      { label: "next", value: nextSteps[0] ?? "regents wallet agentic status --json" },
    ]),
  );
};

export async function runWalletAgenticStatus(args: ParsedCliArgs): Promise<number> {
  printAwal(args, await runAwalJson(["status", "--json"]), ["regents wallet agentic balance --chain base --json"]);
  return 0;
}

export async function runWalletAgenticLogin(args: ParsedCliArgs): Promise<number> {
  const email = requireArg(getFlag(args, "email"), "--email");
  printAwal(
    args,
    await runAwalJson(["auth", "login", email, "--json"]),
    ["regents wallet agentic verify --flow-id <flow-id> --otp <code> --json"],
  );
  return 0;
}

export async function runWalletAgenticVerify(args: ParsedCliArgs): Promise<number> {
  const flowId = requireArg(getFlag(args, "flow-id"), "--flow-id");
  const otp = requireArg(getFlag(args, "otp"), "--otp");
  printAwal(args, await runAwalJson(["auth", "verify", flowId, otp, "--json"]), ["regents wallet agentic balance --chain base --json"]);
  return 0;
}

export async function runWalletAgenticBalance(args: ParsedCliArgs): Promise<number> {
  printAwal(
    args,
    await runAwalJson(["balance", "--chain", chain(args), "--json"]),
    ["regents budget grant --agent <agent-id> --amount-usdc 10 --max-payment-usdc 0.25 --mode techtree_research --rail agentic-wallet --expires 7d"],
  );
  return 0;
}

export async function runWalletAgenticFund(args: ParsedCliArgs): Promise<number> {
  const selectedChain = chain(args);
  const amount = requireArg(getFlag(args, "amount-usdc"), "--amount-usdc");
  const payload = {
    ok: true,
    provider: "coinbase-agentic-wallet",
    chain: selectedChain,
    amount_usdc: amount,
    next_steps: [
      "Open Agentic Wallet and use Fund.",
      "Choose Base USDC and complete the funding step yourself.",
      "regents wallet agentic balance --chain base --json",
    ],
    warning: "Keep meaningful funds in a Safe treasury, not in Agentic Wallet.",
  };

  if (getBooleanFlag(args, "json")) {
    printJson(payload);
    return 0;
  }

  printText(
    renderKeyValuePanel("◆ FUND AGENTIC WALLET", [
      { label: "amount", value: `${amount} USDC` },
      { label: "chain", value: selectedChain },
      { label: "next", value: "regents wallet agentic balance --chain base --json" },
      { label: "action", value: "Open Agentic Wallet and use Fund." },
      { label: "note", value: "Keep meaningful funds in a Safe treasury." },
    ]),
  );
  return 0;
}
