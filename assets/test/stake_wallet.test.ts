import {describe, expect, it, vi} from "vitest"
import {
  encodeFunctionData,
  getAddress,
  parseAbi,
  type Abi,
  type Address,
  type Hash,
  type Hex,
} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import stakingAbiJson from "../../contracts/abi/regent-revenue-staking.json"
import {
  executePreparedStakingAction,
  type PreparedStakingAction,
  type StakingAction,
  type StakingClients,
} from "../js/wallet_actions/staking"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const otherWallet = getAddress("0x2222222222222222222222222222222222222222")
const staking = getAddress(chainManifest.contracts.regent_revenue_staking.address)
const token = getAddress(
  chainManifest.contracts.regent_revenue_staking.onchain_constants.stake_token,
)
const stakingAbi = stakingAbiJson as Abi
const amount = 1_500_000_000_000_000_000n
const hash = `0x${"ab".repeat(32)}` as Hash
const provider = {request: vi.fn(async () => undefined)}
const otherProvider = {request: vi.fn(async () => undefined)}
const selected = () => ({address: wallet, provider})

const actionCases: Array<{
  action: StakingAction
  arguments: PreparedStakingAction["arguments"]
  data: Hex
}> = [
  {
    action: "stake",
    arguments: {amount_atomic: amount.toString(), receiver: wallet},
    data: encodeFunctionData({
      abi: stakingAbi,
      functionName: "stake",
      args: [amount, wallet],
    }),
  },
  {
    action: "unstake",
    arguments: {amount_atomic: amount.toString(), recipient: wallet},
    data: encodeFunctionData({
      abi: stakingAbi,
      functionName: "unstake",
      args: [amount, wallet],
    }),
  },
  {
    action: "claim_usdc",
    arguments: {recipient: wallet},
    data: encodeFunctionData({abi: stakingAbi, functionName: "claimUSDC", args: [wallet]}),
  },
  {
    action: "claim_regent",
    arguments: {recipient: wallet},
    data: encodeFunctionData({abi: stakingAbi, functionName: "claimRegent", args: [wallet]}),
  },
  {
    action: "claim_and_restake_regent",
    arguments: {},
    data: encodeFunctionData({abi: stakingAbi, functionName: "claimAndRestakeRegent"}),
  },
]

function envelope(action: StakingAction = "stake", withApproval = false): PreparedStakingAction {
  const shape = actionCases.find(candidate => candidate.action === action)!
  const actionId = crypto.randomUUID()
  const approvalData = encodeFunctionData({
    abi: parseAbi(["function approve(address spender,uint256 amount)"]),
    functionName: "approve",
    args: [staking, amount],
  })

  return {
    action_id: actionId,
    idempotency_key: actionId,
    confirmation_token: "signed",
    resource: "regent_staking",
    action,
    chain_id: 8453,
    to: staking,
    value: "0",
    data: shape.data,
    expected_signer: wallet,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Stake",
    arguments: {...shape.arguments},
    approval: withApproval
      ? {
          token,
          spender: staking,
          amount: amount.toString(),
          data: approvalData,
          mode: "exact",
        }
      : null,
  }
}

function clients(overrides: Partial<StakingClients> = {}): StakingClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    allowance: vi.fn(async () => amount),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => hash),
    ...overrides,
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void
  const promise = new Promise<T>(done => (resolve = done))
  return {promise, resolve}
}

describe("all five direct staking calldata shapes", () => {
  it.each(actionCases)("sends exact $action bytes with zero value", async ({action, data}) => {
    const rpc = clients()

    await executePreparedStakingAction(envelope(action), provider, rpc, selected)

    expect(rpc.send).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledWith({account: wallet, to: staking, data, value: 0n})
  })
})

describe("Stake approval remains two independent wallet prompts", () => {
  it("asks for exact approval then Stake without a receipt or allowance reread", async () => {
    const rpc = clients({allowance: vi.fn(async () => 0n)})

    await executePreparedStakingAction(envelope("stake", true), provider, rpc, selected)

    expect(rpc.send).toHaveBeenCalledTimes(2)
    expect(vi.mocked(rpc.send).mock.calls.map(([request]) => request.to)).toEqual([token, staking])
    expect(rpc.allowance).toHaveBeenCalledOnce()
  })

  it.each([
    ["missing", (prepared: PreparedStakingAction): void => void (prepared.approval = null)],
    [
      "token",
      (prepared: PreparedStakingAction): void => void (prepared.approval!.token = otherWallet),
    ],
    [
      "spender",
      (prepared: PreparedStakingAction): void => void (prepared.approval!.spender = otherWallet),
    ],
    ["amount", (prepared: PreparedStakingAction): void => void (prepared.approval!.amount = "1")],
    [
      "calldata",
      (prepared: PreparedStakingAction): void =>
        void (prepared.approval!.data = "0xdeadbeef"),
    ],
    [
      "mode",
      (prepared: PreparedStakingAction): void =>
        void (prepared.approval!.mode = "other" as "exact"),
    ],
  ] as const)("refuses malformed approval $0 before send", async (_name, mutate) => {
    const prepared = envelope("stake", true)
    mutate(prepared)
    const rpc = clients({allowance: vi.fn(async () => 0n)})

    await expect(
      executePreparedStakingAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })
})

describe("staking drift fails before a wallet prompt", () => {
  it.each([
    [
      "expired envelope",
      (prepared: PreparedStakingAction): void =>
        void (prepared.expires_at = new Date(Date.now() - 1_000).toISOString()),
    ],
    ["target", (prepared: PreparedStakingAction): void => void (prepared.to = otherWallet)],
    [
      "native value",
      (prepared: PreparedStakingAction): void => void (prepared.value = "1" as "0"),
    ],
    [
      "signer",
      (prepared: PreparedStakingAction): void => void (prepared.expected_signer = otherWallet),
    ],
    [
      "recipient",
      (prepared: PreparedStakingAction): void =>
        void (prepared.arguments.receiver = otherWallet),
    ],
    [
      "calldata",
      (prepared: PreparedStakingAction): void => void (prepared.data = "0xdeadbeef"),
    ],
  ] as const)("refuses changed $0", async (_name, mutate) => {
    const prepared = envelope()
    mutate(prepared)
    const rpc = clients()

    await expect(
      executePreparedStakingAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("switches once, then refuses a chain that drifts after simulation", async () => {
    const chainId = vi
      .fn<StakingClients["chainId"]>()
      .mockResolvedValueOnce(1)
      .mockResolvedValueOnce(8453)
      .mockResolvedValueOnce(1)
    const rpc = clients({chainId})

    await expect(
      executePreparedStakingAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow("Switch to Base")
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the current Privy selection to retain the exact provider", async () => {
    const rpc = clients()

    await expect(
      executePreparedStakingAction(envelope(), provider, rpc, () => ({
        address: wallet,
        provider: otherProvider,
      })),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the selected provider's current account to remain the signer", async () => {
    const rpc = clients({addresses: vi.fn(async () => [otherWallet])})

    await expect(
      executePreparedStakingAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("rechecks after approval returns and suppresses only the later Stake prompt", async () => {
    const approval = deferred<Hash>()
    const send = vi
      .fn<StakingClients["send"]>()
      .mockImplementationOnce(async () => approval.promise)
      .mockResolvedValue(hash)
    const rpc = clients({allowance: vi.fn(async () => 0n), send})
    let active = {address: wallet, provider}

    const execution = executePreparedStakingAction(
      envelope("stake", true),
      provider,
      rpc,
      () => active,
    )

    await vi.waitFor(() => expect(send).toHaveBeenCalledOnce())
    active = {address: otherWallet, provider}
    approval.resolve(hash)

    await expect(execution).rejects.toThrow()
    expect(send).toHaveBeenCalledOnce()
  })
})
