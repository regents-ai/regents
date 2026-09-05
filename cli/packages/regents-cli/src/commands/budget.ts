import { CliUsageError } from "../cli-usage-error.js";
import {
  createBudget,
  findBudget,
  parseBudgetExpiry,
  readBudgetFile,
  revokeBudget,
  type BudgetMode,
  type PaymentRail,
} from "../internal-runtime/budget-store.js";
import { loadConfig } from "../internal-runtime/config.js";
import { getBooleanFlag, getFlag, getFlags, requireArg, type ParsedCliArgs } from "../parse.js";
import { printJson, printText, renderKeyValuePanel } from "../printer.js";

const printBudget = (args: ParsedCliArgs, payload: unknown): void => {
  if (getBooleanFlag(args, "json")) {
    printJson(payload);
    return;
  }

  const budget = Array.isArray((payload as { budgets?: unknown }).budgets)
    ? undefined
    : (payload as { budget?: { budget_id?: string; remaining_usdc?: string; status?: string } }).budget;

  if (budget) {
    const nextSteps = (payload as { next_steps?: string[] }).next_steps ?? [];
    printText(
      renderKeyValuePanel("◆ REGENT BUDGET", [
        { label: "budget", value: budget.budget_id ?? "" },
        { label: "remaining", value: budget.remaining_usdc ?? "" },
        { label: "status", value: budget.status ?? "" },
        ...(nextSteps[0] ? [{ label: "next", value: nextSteps[0] }] : []),
      ]),
    );
    return;
  }

  printJson(payload);
};

const requireMode = (value: string | undefined): BudgetMode => {
  if (value === "techtree_research" || value === "paid_service") {
    return value;
  }

  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--mode must be techtree_research or paid_service.",
    validValues: ["techtree_research", "paid_service"],
  });
};

const requireRail = (value: string | undefined): PaymentRail => {
  if (value === "regent-wallet" || value === "agentic-wallet") {
    return value;
  }

  throw new CliUsageError({
    code: "invalid_flag_value",
    message: "--rail must be regent-wallet or agentic-wallet.",
    validValues: ["regent-wallet", "agentic-wallet"],
  });
};

export async function runBudgetGrant(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budget = createBudget(config, {
    agent_id: requireArg(getFlag(args, "agent"), "--agent"),
    amount_usdc: requireArg(getFlag(args, "amount-usdc"), "--amount-usdc"),
    max_payment_usdc: requireArg(getFlag(args, "max-payment-usdc"), "--max-payment-usdc"),
    mode: requireMode(getFlag(args, "mode")),
    rail: requireRail(getFlag(args, "rail")),
    allowed_hosts: getFlags(args, "allow-host"),
    expires_at: parseBudgetExpiry(requireArg(getFlag(args, "expires"), "--expires")),
  });

  printBudget(args, {
    ok: true,
    budget,
    next_steps: [
      "regents x402 search \"research data\" --json",
      `regents x402 pay <url> --budget ${budget.budget_id} --max-usdc ${budget.max_payment_usdc} --rail ${budget.rail} --receipt --json`,
    ],
  });
  return 0;
}

export async function runBudgetStatus(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budgetId = getFlag(args, "budget");
  if (budgetId) {
    const budget = findBudget(config, budgetId);
    printBudget(args, {
      ok: true,
      budget,
      next_steps: [
        `regents budget ledger --budget ${budget.budget_id}`,
        `regents x402 pay <url> --budget ${budget.budget_id} --max-usdc ${budget.max_payment_usdc} --rail ${budget.rail} --receipt --json`,
      ],
    });
    return 0;
  }

  const agentId = getFlag(args, "agent");
  const budgets = readBudgetFile(config).budgets.filter((budget) => !agentId || budget.agent_id === agentId);
  printJson({
    ok: true,
    budgets,
    next_steps: budgets[0]
      ? [`regents budget ledger --budget ${budgets[0].budget_id}`]
      : ["regents budget grant --agent <agent-id> --amount-usdc 10 --max-payment-usdc 0.25 --mode techtree_research --rail agentic-wallet --expires 7d"],
  });
  return 0;
}

export async function runBudgetLedger(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budget = findBudget(config, requireArg(getFlag(args, "budget"), "--budget"));
  printJson({
    ok: true,
    budget_id: budget.budget_id,
    ledger: budget.ledger,
    next_steps: [`regents x402 pay <url> --budget ${budget.budget_id} --max-usdc ${budget.max_payment_usdc} --rail ${budget.rail} --receipt --json`],
  });
  return 0;
}

export async function runBudgetRevoke(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = loadConfig(configPath);
  const budget = revokeBudget(config, requireArg(getFlag(args, "budget"), "--budget"));
  printBudget(args, { ok: true, budget, next_steps: ["regents budget status --json"] });
  return 0;
}
