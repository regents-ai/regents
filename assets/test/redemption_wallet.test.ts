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
import redeemerAbiJson from "../../contracts/abi/animata-redeemer.json"
import {
  executePreparedRedemptionAction,
  type PreparedRedemptionAction,
  type RedemptionAction,
  type RedemptionClients,
} from "../js/wallet_actions/redemption"

const manifest = chainManifest.contracts.animata_redeemer
const wallet = getAddress("0x1111111111111111111111111111111111111111")
const otherWallet = getAddress("0x2222222222222222222222222222222222222222")
const redeemer = getAddress(manifest.address)
const animataI = getAddress(manifest.onchain_constants.animata_i)
const animataII = getAddress(manifest.onchain_constants.animata_ii)
const usdc = getAddress(manifest.onchain_constants.usdc)
const price = BigInt(manifest.onchain_constants.usdc_price_atomic)
const redeemerAbi = redeemerAbiJson as Abi
const erc20Approval = parseAbi(["function approve(address spender,uint256 amount)"])
const erc721Approval = parseAbi([
  "function setApprovalForAll(address operator,bool approved)",
])
const hash = `0x${"ab".repeat(32)}` as Hash
const provider = {request: vi.fn(async () => undefined)}
const otherProvider = {request: vi.fn(async () => undefined)}
const selected = () => ({address: wallet, provider})

const actionCases: Array<{
  action: RedemptionAction
  to: Address
  arguments: PreparedRedemptionAction["arguments"]
  data: Hex
}> = [
  {
    action: "approve_nft_collection",
    to: animataI,
    arguments: {collection: animataI, operator: redeemer, approved: true},
    data: encodeFunctionData({
      abi: erc721Approval,
      functionName: "setApprovalForAll",
      args: [redeemer, true],
    }),
  },
  {
    action: "approve_exact_usdc",
    to: usdc,
    arguments: {spender: redeemer, amount_atomic: price.toString(), mode: "exact"},
    data: encodeFunctionData({
      abi: erc20Approval,
      functionName: "approve",
      args: [redeemer, price],
    }),
  },
  {
    action: "redeem",
    to: redeemer,
    arguments: {collection: animataII, token_id: 42},
    data: encodeFunctionData({
      abi: redeemerAbi,
      functionName: "redeem",
      args: [animataII, 42n],
    }),
  },
  {
    action: "claim",
    to: redeemer,
    arguments: {},
    data: encodeFunctionData({abi: redeemerAbi, functionName: "claim"}),
  },
]

function envelope(action: RedemptionAction = "claim"): PreparedRedemptionAction {
  const shape = actionCases.find(candidate => candidate.action === action)!
  const actionId = crypto.randomUUID()
  return {
    action_id: actionId,
    idempotency_key: actionId,
    confirmation_token: "signed",
    resource: "animata_redemption",
    action,
    chain_id: 8453,
    to: shape.to,
    value: "0",
    data: shape.data,
    expected_signer: wallet,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Redeem",
    arguments: {...shape.arguments},
  }
}

function clients(overrides: Partial<RedemptionClients> = {}): RedemptionClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
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

describe("all four direct redemption calldata shapes", () => {
  it.each(actionCases)("sends exact $action bytes with zero value", async shape => {
    const rpc = clients()

    await executePreparedRedemptionAction(envelope(shape.action), provider, rpc, selected)

    expect(rpc.send).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledWith({
      account: wallet,
      to: shape.to,
      data: shape.data,
      value: 0n,
    })
  })
})

describe("redemption drift fails before a wallet prompt", () => {
  it.each([
    [
      "expired envelope",
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.expires_at = new Date(Date.now() - 1_000).toISOString()),
    ],
    ["target", (prepared: PreparedRedemptionAction): void => void (prepared.to = otherWallet)],
    [
      "native value",
      (prepared: PreparedRedemptionAction): void => void (prepared.value = "1" as "0"),
    ],
    [
      "signer",
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.expected_signer = otherWallet),
    ],
    [
      "calldata",
      (prepared: PreparedRedemptionAction): void => void (prepared.data = "0xdeadbeef"),
    ],
  ] as const)("refuses changed $0", async (_name, mutate) => {
    const prepared = envelope()
    mutate(prepared)
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it.each([
    [
      "NFT collection",
      "approve_nft_collection" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.collection = otherWallet),
    ],
    [
      "NFT approval",
      "approve_nft_collection" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.approved = false),
    ],
    [
      "USDC approval",
      "approve_exact_usdc" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.amount_atomic = "1"),
    ],
    [
      "redeem collection",
      "redeem" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.collection = otherWallet),
    ],
    [
      "token ID",
      "redeem" as const,
      (prepared: PreparedRedemptionAction): void =>
        void (prepared.arguments.token_id = 1_000),
    ],
  ] as const)("refuses changed $0", async (_name, action, mutate) => {
    const prepared = envelope(action)
    mutate(prepared)
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(prepared, provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("switches once, then refuses a chain that drifts during simulation", async () => {
    const chainId = vi
      .fn<RedemptionClients["chainId"]>()
      .mockResolvedValueOnce(1)
      .mockResolvedValueOnce(8453)
      .mockResolvedValueOnce(1)
    const rpc = clients({chainId})

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow("Switch to Base")
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the current Privy selection to retain the exact provider", async () => {
    const rpc = clients()

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, () => ({
        address: wallet,
        provider: otherProvider,
      })),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("requires the selected provider's current account to remain the signer", async () => {
    const rpc = clients({addresses: vi.fn(async () => [otherWallet])})

    await expect(
      executePreparedRedemptionAction(envelope(), provider, rpc, selected),
    ).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("rechecks the Privy provider after a deferred simulation", async () => {
    const simulation = deferred<void>()
    const rpc = clients({simulate: vi.fn(async () => simulation.promise)})
    let active = {address: wallet, provider}

    const execution = executePreparedRedemptionAction(envelope(), provider, rpc, () => active)
    await vi.waitFor(() => expect(rpc.simulate).toHaveBeenCalledOnce())

    active = {address: wallet, provider: otherProvider}
    simulation.resolve()

    await expect(execution).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })
})
