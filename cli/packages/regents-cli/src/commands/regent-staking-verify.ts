import { createPublicClient, http } from "viem";

import { readIdentityReceipt } from "../internal-runtime/identity/cache.js";
import { getBooleanFlag, getFlag, parseCliArgs, type ParsedCliArgs } from "../parse.js";
import {
  CLI_PALETTE,
  printJson,
  printText,
  renderKeyValuePanel,
  renderPanel,
  renderTablePanel,
} from "../printer.js";
import { requestProductJson } from "./product-http.js";

type CheckStatus = "MATCH" | "MISMATCH" | "UNVERIFIABLE";

interface VerifyCheck {
  readonly item: string;
  readonly status: CheckStatus;
  readonly detail: string;
  readonly reason?: string;
  readonly next?: string;
}

// Minimal read ABI for RegentRevenueStaking. The Platform staking API does not
// publish the read ABI, so the CLI vendors it here. These names are pinned to
// the deployed RegentRevenueStaking contract source
// (autolaunch/contracts/src/revenue/RegentRevenueStaking.sol):
// - `stakedBalance(address)` public mapping getter -> uint256
// - `previewClaimableUSDC(address)` view -> uint256
// - `previewClaimableRegent(address)` view -> uint256
// - `totalStaked()` public state getter -> uint256
// - `paused()` public state getter -> bool
// They must stay in sync with that source if the contract ABI changes.
const STAKING_READ_ABI = [
  {
    type: "function",
    name: "stakedBalance",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "previewClaimableUSDC",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "previewClaimableRegent",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalStaked",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "paused",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

// Minimal ERC-20 read ABI for the stake-token balance check.
const ERC20_BALANCE_OF_ABI = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// Every row here is money/staking, so the chain wins for all of them.
const STAKING_MISMATCH_NEXT =
  "chain wins for staking. Trust the chain numbers; if the API stays stale, this is incident class staking_claims (owner: platform).";

const errorText = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

const asRecord = (value: unknown): Record<string, unknown> | null =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;

const asText = (value: unknown): string | null =>
  typeof value === "string" && value.trim() !== "" ? value : null;

const asBool = (value: unknown): boolean | null =>
  typeof value === "boolean" ? value : null;

const addressPattern = /^0x[0-9a-fA-F]{40}$/u;

const isAddress = (value: unknown): value is `0x${string}` =>
  typeof value === "string" && addressPattern.test(value);

const rpcUrl = (args: ParsedCliArgs): string | undefined =>
  getFlag(args, "rpc-url") ?? process.env.BASE_MAINNET_RPC_URL ?? process.env.BASE_RPC_URL;

const resolveWallet = (args: ParsedCliArgs): string | null => {
  const positional = args.positionals[2];
  if (positional && positional.trim() !== "") {
    return positional;
  }
  const receipt = readIdentityReceipt();
  return receipt?.address ?? null;
};

const fetchStaking = async (
  path: string,
  configPath?: string,
): Promise<{ readonly payload: Record<string, unknown> | null; readonly error: string | null }> => {
  try {
    const payload = await requestProductJson<Record<string, unknown>>("GET", path, {
      requireAgentAuth: true,
      authAudience: "regent-services",
      service: "platform",
      commandName: "regents regent-staking verify",
      configPath,
    });
    return { payload, error: null };
  } catch (error) {
    return { payload: null, error: errorText(error) };
  }
};

// Compare a published raw value against a chain-read raw value. Both are decimal
// integer strings (raw atomic units), so a string compare is exact.
const rawMatchCheck = (
  item: string,
  apiRaw: string | null,
  chainRaw: bigint | null,
): VerifyCheck => {
  if (apiRaw === null && chainRaw === null) {
    return {
      item,
      status: "UNVERIFIABLE",
      detail: "neither the API nor the chain published a value to compare",
    };
  }
  if (chainRaw === null) {
    return { item, status: "UNVERIFIABLE", detail: "the chain read returned no value" };
  }
  if (apiRaw === null) {
    return {
      item,
      status: "MISMATCH",
      detail: `the API published no value, but the chain reads ${chainRaw.toString()}`,
      next: STAKING_MISMATCH_NEXT,
    };
  }

  const chainText = chainRaw.toString();
  if (apiRaw === chainText) {
    return { item, status: "MATCH", detail: `API and chain agree on ${chainText}` };
  }

  return {
    item,
    status: "MISMATCH",
    detail: `the API reports ${apiRaw} but the chain reads ${chainText}`,
    next: STAKING_MISMATCH_NEXT,
  };
};

const buildVerification = async (args: ParsedCliArgs, configPath?: string) => {
  const wallet = resolveWallet(args);
  const checks: VerifyCheck[] = [];

  if (!wallet) {
    checks.push({
      item: "wallet",
      status: "UNVERIFIABLE",
      detail: "no wallet to check",
      reason:
        "Pass a wallet address, or run `regents identity ensure` first so the saved Agent wallet can be used.",
    });
    return {
      ok: true,
      command: "regent-staking verify",
      status: "ready",
      wallet: null,
      checks,
      api_view: { overview: null, account: null },
      chain_view: {} as Record<string, unknown>,
    };
  }

  const { payload: overview, error: overviewError } = await fetchStaking(
    "/api/shared/regent/staking",
    configPath,
  );
  const { payload: account } = await fetchStaking(
    `/api/shared/regent/staking/account/${encodeURIComponent(wallet)}`,
    configPath,
  );

  const chainView: Record<string, unknown> = {};
  const apiState = asRecord(account) ?? asRecord(overview);

  if (!apiState) {
    checks.push({
      item: "staking overview",
      status: "UNVERIFIABLE",
      detail: `wallet ${wallet}`,
      reason:
        overviewError ??
        "Platform did not return the staking state. Run `regents auth login` first.",
    });
    return {
      ok: true,
      command: "regent-staking verify",
      status: "ready",
      wallet,
      checks,
      api_view: { overview, account },
      chain_view: chainView,
    };
  }

  const contractAddress = asText(apiState.contract_address);
  const stakeTokenAddress = asText(apiState.stake_token_address);
  const apiTotalStaked = asText(apiState.total_staked_raw);
  const apiWalletStake = asText(apiState.wallet_stake_balance_raw);
  const apiClaimableUsdc = asText(apiState.wallet_claimable_usdc_raw);
  const apiClaimableRegent = asText(apiState.wallet_claimable_regent_raw);
  const apiWalletToken = asText(apiState.wallet_token_balance_raw);
  const apiPaused = asBool(apiState.paused);

  const rpc = rpcUrl(args);

  if (!rpc) {
    const reason =
      "Set BASE_MAINNET_RPC_URL or BASE_RPC_URL, or pass --rpc-url, to read the staking contract onchain.";
    for (const item of [
      "staking contract deployed",
      "total staked",
      "wallet staked balance",
      "wallet claimable USDC",
      "wallet claimable REGENT",
      "wallet REGENT balance",
      "paused flag",
    ]) {
      checks.push({ item, status: "UNVERIFIABLE", detail: contractAddress ?? "staking contract", reason });
    }
  } else if (!contractAddress || !isAddress(contractAddress)) {
    checks.push({
      item: "staking contract deployed",
      status: "UNVERIFIABLE",
      detail: "no contract address",
      reason: "The staking API did not publish a valid contract_address to verify.",
    });
  } else {
    const publicClient = createPublicClient({ transport: http(rpc) });
    const contract = contractAddress;

    try {
      const bytecode = await publicClient.getBytecode({ address: contract });
      const hasCode = typeof bytecode === "string" && bytecode !== "0x" && bytecode.length > 2;
      chainView.staking_contract = { address: contract, has_code: hasCode };
      if (!hasCode) {
        checks.push({
          item: "staking contract deployed",
          status: "MISMATCH",
          detail: `the published staking contract ${contract} has no deployed code onchain`,
          next: STAKING_MISMATCH_NEXT,
        });
      } else {
        checks.push({
          item: "staking contract deployed",
          status: "MATCH",
          detail: `${contract} is a deployed contract`,
        });
      }
    } catch (error) {
      checks.push({
        item: "staking contract deployed",
        status: "UNVERIFIABLE",
        detail: contract,
        reason: errorText(error),
      });
    }

    const readUint = async (functionName: string, args_: readonly unknown[]): Promise<bigint | null> => {
      try {
        return (await publicClient.readContract({
          address: contract,
          abi: STAKING_READ_ABI,
          functionName: functionName as "totalStaked",
          args: args_ as never,
        })) as bigint;
      } catch {
        return null;
      }
    };

    const walletArg = isAddress(wallet) ? [wallet] : null;

    const chainTotalStaked = await readUint("totalStaked", []);
    chainView.total_staked_raw = chainTotalStaked?.toString() ?? null;
    checks.push(rawMatchCheck("total staked", apiTotalStaked, chainTotalStaked));

    const chainWalletStake = walletArg ? await readUint("stakedBalance", walletArg) : null;
    chainView.wallet_stake_balance_raw = chainWalletStake?.toString() ?? null;
    checks.push(rawMatchCheck("wallet staked balance", apiWalletStake, chainWalletStake));

    const chainClaimableUsdc = walletArg ? await readUint("previewClaimableUSDC", walletArg) : null;
    chainView.wallet_claimable_usdc_raw = chainClaimableUsdc?.toString() ?? null;
    checks.push(rawMatchCheck("wallet claimable USDC", apiClaimableUsdc, chainClaimableUsdc));

    const chainClaimableRegent = walletArg
      ? await readUint("previewClaimableRegent", walletArg)
      : null;
    chainView.wallet_claimable_regent_raw = chainClaimableRegent?.toString() ?? null;
    checks.push(rawMatchCheck("wallet claimable REGENT", apiClaimableRegent, chainClaimableRegent));

    let chainWalletToken: bigint | null = null;
    if (stakeTokenAddress && isAddress(stakeTokenAddress) && walletArg) {
      try {
        chainWalletToken = (await publicClient.readContract({
          address: stakeTokenAddress,
          abi: ERC20_BALANCE_OF_ABI,
          functionName: "balanceOf",
          args: [wallet as `0x${string}`],
        })) as bigint;
      } catch {
        chainWalletToken = null;
      }
    }
    chainView.wallet_token_balance_raw = chainWalletToken?.toString() ?? null;
    checks.push(rawMatchCheck("wallet REGENT balance", apiWalletToken, chainWalletToken));

    let chainPaused: boolean | null = null;
    try {
      chainPaused = (await publicClient.readContract({
        address: contract,
        abi: STAKING_READ_ABI,
        functionName: "paused",
      })) as boolean;
    } catch {
      chainPaused = null;
    }
    chainView.paused = chainPaused;
    if (chainPaused === null) {
      checks.push({ item: "paused flag", status: "UNVERIFIABLE", detail: "the chain paused() read failed" });
    } else if (apiPaused === null) {
      checks.push({
        item: "paused flag",
        status: "MISMATCH",
        detail: `the API published no paused flag, but the chain reads ${chainPaused}`,
        next: STAKING_MISMATCH_NEXT,
      });
    } else if (apiPaused === chainPaused) {
      checks.push({ item: "paused flag", status: "MATCH", detail: `API and chain agree paused is ${chainPaused}` });
    } else {
      checks.push({
        item: "paused flag",
        status: "MISMATCH",
        detail: `the API reports paused ${apiPaused} but the chain reads ${chainPaused}`,
        next: STAKING_MISMATCH_NEXT,
      });
    }
  }

  const mismatched = checks.some((check) => check.status === "MISMATCH");

  return {
    ok: !mismatched,
    command: "regent-staking verify",
    status: mismatched ? "mismatch" : "ready",
    wallet,
    checks,
    api_view: { overview, account },
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
    renderKeyValuePanel("◆ REGENT STAKING VERIFY", [
      {
        label: "status",
        value: result.status,
        valueColor: result.ok ? CLI_PALETTE.emphasis : CLI_PALETTE.error,
      },
      { label: "wallet", value: result.wallet ?? "not ready" },
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

export async function runRegentStakingVerify(
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
