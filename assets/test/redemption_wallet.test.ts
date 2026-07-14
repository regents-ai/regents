import {describe, expect, it, vi} from "vitest"
import {encodeFunctionData, getAddress, parseAbi, type Address, type Hash} from "viem"

import chainManifest from "../../contracts/base-mainnet.json"
import redeemerAbiJson from "../../contracts/abi/animata-redeemer.json"
import {recordSubmittedRedemption} from "../js/hooks/redemption_wallet"
import {
  assertRedemptionEnvelope,
  executePreparedRedemptionAction,
  type PreparedRedemptionAction,
  type RedemptionClients,
} from "../js/wallet_actions/redemption"

const manifest = chainManifest.contracts.animata_redeemer
const wallet = getAddress("0x1111111111111111111111111111111111111111")
const other = getAddress("0x2222222222222222222222222222222222222222")
const redeemer = getAddress(manifest.address)
const animataI = getAddress(manifest.onchain_constants.animata_i)
const resultCollection = getAddress(manifest.onchain_constants.result_collection)
const usdc = getAddress(manifest.onchain_constants.usdc)
const hash = `0x${"ab".repeat(32)}` as Hash
const redeemAbi = redeemerAbiJson
const erc20 = parseAbi(["function approve(address spender,uint256 amount)"])
const erc721 = parseAbi(["function setApprovalForAll(address operator,bool approved)"])

function baseEnvelope(overrides: Partial<PreparedRedemptionAction> = {}): PreparedRedemptionAction {
  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "animata_redemption",
    action: "claim",
    chain_id: 8453,
    to: redeemer,
    value: "0",
    data: encodeFunctionData({abi: redeemAbi, functionName: "claim"}),
    expected_signer: wallet,
    prepared_at: new Date(Date.now() - 1000).toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Claim unlocked REGENT.",
    arguments: {},
    ...overrides,
  }
}

function clients(overrides: Partial<RedemptionClients> = {}): RedemptionClients {
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => hash),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

describe("prepared Animata redemption actions", () => {
  it("submits exactly one reviewed action from the expected wallet", async () => {
    const rpc = clients()
    const submitted = vi.fn()
    const result = await executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc, submitted)

    expect(result).toBe(hash)
    expect(rpc.simulate).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledOnce()
    expect(rpc.receipt).toHaveBeenCalledWith(hash)
    expect(submitted).toHaveBeenCalledWith(hash)
    expect(vi.mocked(rpc.send).mock.calls[0]?.[0]).toEqual({
      account: wallet,
      to: redeemer,
      data: baseEnvelope().data,
      value: 0n,
    })
  })

  it("re-encodes and validates all four separate action shapes", () => {
    const nft = baseEnvelope({
      action: "approve_nft_collection",
      to: animataI,
      arguments: {collection: animataI, operator: redeemer, approved: true},
      data: encodeFunctionData({abi: erc721, functionName: "setApprovalForAll", args: [redeemer, true]}),
    })
    const approval = baseEnvelope({
      action: "approve_exact_usdc",
      to: usdc,
      arguments: {spender: redeemer, amount_atomic: "80000000", mode: "exact"},
      data: encodeFunctionData({abi: erc20, functionName: "approve", args: [redeemer, 80_000_000n]}),
    })
    const redeem = baseEnvelope({
      action: "redeem",
      arguments: {collection: animataI, token_id: 42},
      data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [animataI, 42n]}),
    })

    for (const envelope of [nft, approval, redeem, baseEnvelope()]) {
      expect(() => assertRedemptionEnvelope(envelope)).not.toThrow()
    }
  })

  it("rejects signer, chain, target, value, collection, token, approval and calldata drift", async () => {
    const mutations: PreparedRedemptionAction[] = [
      baseEnvelope({chain_id: 1 as 8453}),
      baseEnvelope({to: other}),
      baseEnvelope({value: "1" as "0"}),
      baseEnvelope({data: "0xdeadbeef"}),
      baseEnvelope({resource: "other" as "animata_redemption"}),
      baseEnvelope({idempotency_key: "other"}),
      baseEnvelope({expires_at: new Date(Date.now() - 1000).toISOString()}),
      baseEnvelope({
        action: "redeem",
        arguments: {collection: resultCollection, token_id: 42},
        data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [resultCollection, 42n]}),
      }),
      baseEnvelope({
        action: "redeem",
        arguments: {collection: animataI, token_id: 1000},
        data: encodeFunctionData({abi: redeemAbi, functionName: "redeem", args: [animataI, 1000n]}),
      }),
      baseEnvelope({
        action: "approve_exact_usdc",
        to: usdc,
        arguments: {spender: redeemer, amount_atomic: "80000001", mode: "exact"},
        data: encodeFunctionData({abi: erc20, functionName: "approve", args: [redeemer, 80_000_001n]}),
      }),
    ]

    for (const envelope of mutations) {
      await expect(executePreparedRedemptionAction(envelope, {request: vi.fn()}, clients())).rejects.toBeInstanceOf(Error)
    }

    await expect(
      executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, clients({addresses: vi.fn(async () => [other])})),
    ).rejects.toThrow("connected wallet")
  })

  it("switches to Base then fails closed if the wallet stays on another chain", async () => {
    const chainId = vi.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(1)
    const rpc = clients({chainId})
    await expect(executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc)).rejects.toThrow("Switch to Base")
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.send).not.toHaveBeenCalled()
  })

  it("captures a reverted hash for server verification without resubmitting", async () => {
    const rpc = clients({receipt: vi.fn(async () => ({status: "reverted" as const}))})
    const submitted = vi.fn()

    await expect(
      executePreparedRedemptionAction(baseEnvelope(), {request: vi.fn()}, rpc, submitted),
    ).rejects.toMatchObject({
      code: "action_reverted",
      transactionHash: hash,
    })
    expect(submitted).toHaveBeenCalledOnce()
    expect(rpc.send).toHaveBeenCalledOnce()
  })

  it("notifies the server before best-effort session storage", () => {
    const order: string[] = []
    const storage = {setItem: vi.fn(() => order.push("storage"))}
    const push = vi.fn(() => order.push("server"))
    const stored = recordSubmittedRedemption(baseEnvelope(), hash, push, storage)

    expect(order).toEqual(["server", "storage"])
    expect(stored.transaction_hash).toBe(hash)
    expect(push).toHaveBeenCalledWith({action_id: "action", transaction_hash: hash})
  })

  it("keeps the submitted hash when session storage fails after server notification", () => {
    const push = vi.fn()
    const storage = {setItem: vi.fn(() => { throw new Error("quota") })}

    const stored = recordSubmittedRedemption(baseEnvelope(), hash, push, storage)

    expect(push).toHaveBeenCalledOnce()
    expect(stored.transaction_hash).toBe(hash)
    expect(stored.envelope.action_id).toBe("action")
  })
})
