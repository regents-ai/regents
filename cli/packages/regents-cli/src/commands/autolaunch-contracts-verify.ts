import { createPublicClient, http } from "viem";

import { getBooleanFlag, getFlag, parseCliArgs, type ParsedCliArgs } from "../parse.js";
import {
  CLI_PALETTE,
  printJson,
  printText,
  renderKeyValuePanel,
  renderPanel,
  renderTablePanel,
} from "../printer.js";
import { loadResolvedPlatformSession, requestPlatformSessionJson } from "./platform.js";
import { requestProductJson } from "./product-http.js";

type CheckStatus = "MATCH" | "MISMATCH" | "UNVERIFIABLE";

interface VerifyCheck {
  readonly item: string;
  readonly status: CheckStatus;
  readonly detail: string;
  readonly reason?: string;
  readonly next?: string;
}

// Minimal read ABI carried by the CLI. The Autolaunch contracts overview does
// not publish ABI fragments, so the CLI owns the owner()/paused() signatures it
// needs to read deployed contracts directly.
const CONTRACT_READ_ABI = [
  {
    type: "function",
    name: "owner",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "paused",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const UNTYPED_OVERVIEW_REASON =
  "Autolaunch contracts overview is untyped; field-level diff needs typed admin/job/subject payloads.";

const NO_BYTECODE_NEXT =
  "Chain wins. The published address is not a deployed contract; report it to Autolaunch (incident class billing/launch_deployment).";

const errorText = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

const addressPattern = /^0x[0-9a-fA-F]{40}$/u;

const isAddress = (value: unknown): value is `0x${string}` =>
  typeof value === "string" && addressPattern.test(value);

// Walk the untyped overview and collect every distinct contract address it
// publishes, remembering the JSON key path so the row reads in product terms.
const collectAddresses = (
  value: unknown,
  pathParts: readonly string[],
  seen: Map<string, string>,
): void => {
  if (isAddress(value)) {
    const key = value.toLowerCase();
    if (!seen.has(key)) {
      seen.set(key, pathParts.join(" ") || "address");
    }
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((entry, index) => collectAddresses(entry, [...pathParts, String(index)], seen));
    return;
  }

  if (value && typeof value === "object") {
    for (const [childKey, childValue] of Object.entries(value as Record<string, unknown>)) {
      collectAddresses(childValue, [...pathParts, childKey.replace(/_/gu, " ")], seen);
    }
  }
};

const rpcUrl = (args: ParsedCliArgs): string | undefined =>
  getFlag(args, "rpc-url") ?? process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL;

const scopeForArgs = (
  args: ParsedCliArgs,
): {
  readonly scope: string;
  readonly path: string;
  readonly label: string;
  readonly auth: "agent" | "app";
} => {
  const job = getFlag(args, "job");
  if (job) {
    return {
      scope: "job",
      path: `/api/autolaunch/v1/agent/contracts/jobs/${encodeURIComponent(job)}`,
      label: `job ${job}`,
      auth: "agent",
    };
  }

  const subject = getFlag(args, "subject");
  if (subject) {
    return {
      scope: "subject",
      path: `/api/autolaunch/v1/agent/contracts/subjects/${encodeURIComponent(subject)}`,
      label: `subject ${subject}`,
      auth: "agent",
    };
  }

  return {
    scope: "admin",
    path: "/api/autolaunch/v1/app/contracts/admin",
    label: "admin contracts",
    auth: "app",
  };
};

const buildVerification = async (args: ParsedCliArgs, configPath?: string) => {
  const { scope, path, label, auth } = scopeForArgs(args);
  const checks: VerifyCheck[] = [];
  let apiView: unknown = null;
  let apiError: string | null = null;

  try {
    if (auth === "app") {
      const { origin, session } = await loadResolvedPlatformSession(args);
      const { data } = await requestPlatformSessionJson({
        origin,
        path,
        method: "GET",
        session,
        commandName: "regents autolaunch contracts verify",
        configPath,
      });
      apiView = data;
    } else {
      apiView = await requestProductJson<Record<string, unknown>>("GET", path, {
        requireAgentAuth: true,
        authAudience: "autolaunch",
        service: "autolaunch",
        commandName: "regents autolaunch contracts verify",
        configPath,
      });
    }
  } catch (error) {
    apiError = errorText(error);
  }

  const chainView: Record<string, unknown> = {};

  if (apiError !== null) {
    checks.push({
      item: `${label} overview`,
      status: "UNVERIFIABLE",
      detail: "Autolaunch did not return the contracts overview.",
      reason: apiError,
    });
  } else {
    const addresses = new Map<string, string>();
    collectAddresses(apiView, [], addresses);
    const rpc = rpcUrl(args);

    if (addresses.size === 0) {
      checks.push({
        item: `${label} addresses`,
        status: "UNVERIFIABLE",
        detail: "The overview published no contract addresses to verify.",
        reason: UNTYPED_OVERVIEW_REASON,
      });
    } else if (!rpc) {
      for (const [address, fieldLabel] of addresses) {
        checks.push({
          item: `deployed code (${fieldLabel})`,
          status: "UNVERIFIABLE",
          detail: `published address ${address}`,
          reason: "Set BASE_MAINNET_RPC_URL or BASE_RPC_URL, or pass --rpc-url, to verify deployed code onchain.",
        });
      }
    } else {
      const publicClient = createPublicClient({ transport: http(rpc) });

      for (const [address, fieldLabel] of addresses) {
        try {
          const bytecode = await publicClient.getBytecode({ address: address as `0x${string}` });
          const hasCode = typeof bytecode === "string" && bytecode !== "0x" && bytecode.length > 2;
          chainView[address] = { has_code: hasCode };

          if (!hasCode) {
            checks.push({
              item: `deployed code (${fieldLabel})`,
              status: "MISMATCH",
              detail: `the published address ${address} has no deployed code onchain`,
              next: NO_BYTECODE_NEXT,
            });
            continue;
          }

          // Surface the chain-side owner/paused values where the contract
          // exposes them, for the detail and chain_view payload only.
          let ownerOnchain: string | null = null;
          let pausedOnchain: boolean | null = null;
          try {
            ownerOnchain = (await publicClient.readContract({
              address: address as `0x${string}`,
              abi: CONTRACT_READ_ABI,
              functionName: "owner",
            })) as string;
          } catch {
            ownerOnchain = null;
          }
          try {
            pausedOnchain = (await publicClient.readContract({
              address: address as `0x${string}`,
              abi: CONTRACT_READ_ABI,
              functionName: "paused",
            })) as boolean;
          } catch {
            pausedOnchain = null;
          }
          chainView[address] = { has_code: true, owner: ownerOnchain, paused: pausedOnchain };

          checks.push({
            item: `deployed code (${fieldLabel})`,
            status: "MATCH",
            detail: `the published address ${address} is a deployed contract`,
          });
        } catch (error) {
          checks.push({
            item: `deployed code (${fieldLabel})`,
            status: "UNVERIFIABLE",
            detail: `published address ${address}`,
            reason: errorText(error),
          });
        }
      }

      // The overview is untyped, so there is no published expected owner or
      // paused value to diff the chain reads against.
      checks.push({
        item: `owner / paused match (${label})`,
        status: "UNVERIFIABLE",
        detail: "Chain owner/paused were read, but the overview publishes no expected values to compare.",
        reason: UNTYPED_OVERVIEW_REASON,
      });
    }
  }

  const mismatched = checks.some((check) => check.status === "MISMATCH");

  return {
    ok: !mismatched,
    command: "autolaunch contracts verify",
    status: mismatched ? "mismatch" : "ready",
    scope,
    checks,
    api_view: apiView,
    chain_view: chainView,
  };
};

const statusColor = (status: CheckStatus): string => {
  if (status === "MATCH") {
    return CLI_PALETTE.emphasis;
  }
  if (status === "MISMATCH") {
    return CLI_PALETTE.error;
  }
  return CLI_PALETTE.secondary;
};

const checkRow = (check: VerifyCheck) => ({
  cells: [
    check.item,
    check.status === "UNVERIFIABLE" ? `UNVERIFIABLE(${check.reason ?? "unknown"})` : check.status,
    check.detail,
  ],
  colors: [undefined, statusColor(check.status), undefined],
});

const renderHuman = (result: Awaited<ReturnType<typeof buildVerification>>): string => {
  const nextLines = result.checks
    .filter((check) => check.next !== undefined)
    .map((check) => `Next: ${check.next}`);

  return [
    renderKeyValuePanel("◆ CONTRACTS VERIFY", [
      {
        label: "status",
        value: result.status,
        valueColor: result.ok ? CLI_PALETTE.emphasis : CLI_PALETTE.error,
      },
      { label: "scope", value: result.scope },
    ], {
      borderColor: CLI_PALETTE.chrome,
      titleColor: CLI_PALETTE.title,
    }),
    renderTablePanel(
      "◆ CHECKS",
      [{ header: "item" }, { header: "status" }, { header: "detail" }],
      result.checks.map(checkRow),
    ),
    ...(nextLines.length > 0 ? [renderPanel("◆ NEXT", nextLines)] : []),
  ].join("\n\n");
};

export async function runAutolaunchContractsVerify(
  args: readonly string[] | ParsedCliArgs,
  configPath?: string,
): Promise<number> {
  const parsedArgs = Array.isArray(args) ? parseCliArgs(args) : (args as ParsedCliArgs);
  const json = getBooleanFlag(parsedArgs, "json");
  const result = await buildVerification(parsedArgs, configPath);

  if (json) {
    printJson(result);
  } else {
    printText(renderHuman(result));
  }

  return result.ok ? 0 : 1;
}
