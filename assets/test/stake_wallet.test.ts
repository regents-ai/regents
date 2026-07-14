import {describe, expect, it, vi} from "vitest"
import {encodeFunctionData, parseAbi, type Address, type Hash} from "viem"

import {
  executePreparedStakingAction,
  type PreparedStakingAction,
  type StakingClients,
} from "../js/wallet_actions/staking"
import {recordSubmittedAction} from "../js/hooks/stake_wallet"

const wallet = "0x1111111111111111111111111111111111111111" as Address
const staking = "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5" as Address
const token = "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07" as Address
const mainHash = `0x${"ab".repeat(32)}` as Hash
const approvalHash = `0x${"cd".repeat(32)}` as Hash

function envelope(overrides: Partial<PreparedStakingAction> = {}): PreparedStakingAction {
  const amount = 1_500_000_000_000_000_000n
  const data = encodeFunctionData({
    abi: parseAbi(["function stake(uint256 amount,address receiver)"]),
    functionName: "stake",
    args: [amount, wallet],
  })
  const approvalData = encodeFunctionData({
    abi: parseAbi(["function approve(address spender,uint256 amount)"]),
    functionName: "approve",
    args: [staking, amount],
  })

  return {
    action_id: "action",
    idempotency_key: "action",
    confirmation_token: "signed",
    resource: "regent_staking",
    action: "stake",
    chain_id: 8453,
    to: staking,
    value: "0",
    data,
    expected_signer: wallet,
    prepared_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    risk_copy: "Review this action.",
    arguments: {amount_atomic: amount.toString(), receiver: wallet},
    approval: {token, spender: staking, amount: amount.toString(), data: approvalData, mode: "exact"},
    ...overrides,
  }
}

function clients(overrides: Partial<StakingClients> = {}): StakingClients {
  let sends = 0
  return {
    addresses: vi.fn(async () => [wallet]),
    chainId: vi.fn(async () => 8453),
    switchToBase: vi.fn(async () => undefined),
    allowance: vi.fn(async () => 0n),
    simulate: vi.fn(async () => undefined),
    send: vi.fn(async () => (++sends === 1 ? approvalHash : mainHash)),
    receipt: vi.fn(async () => ({status: "success" as const})),
    ...overrides,
  }
}

const provider = {request: vi.fn(async () => undefined)}

describe("staking wallet action", () => {
  it("matches viem ABI bytes and completes exact approval before the stake", async () => {
    const prepared = envelope()
    expect(prepared.data).toBe(
      "0x7acb775700000000000000000000000000000000000000000000000014d1120d7b1600000000000000000000000000001111111111111111111111111111111111111111",
    )

    const approvalBoundary = clients()
    await expect(executePreparedStakingAction(prepared, provider, approvalBoundary)).resolves.toEqual({
      phase: "approval",
      approvalHash,
    })
    expect(approvalBoundary.send).toHaveBeenCalledOnce()
    expect(approvalBoundary.receipt).not.toHaveBeenCalled()

    const mainBoundary = clients({send: vi.fn(async () => mainHash)})
    await expect(
      executePreparedStakingAction(prepared, provider, mainBoundary, {
        existingApprovalHash: approvalHash,
      }),
    ).resolves.toEqual({phase: "action", transactionHash: mainHash, approvalHash})
    expect(mainBoundary.send).toHaveBeenCalledOnce()
    expect(mainBoundary.receipt).toHaveBeenCalledOnce()
  })

  it("notifies the server and retains the hash in memory when session storage throws", () => {
    const push = vi.fn()
    const storage = {
      setItem: vi.fn(() => {
        throw new DOMException("quota", "QuotaExceededError")
      }),
    }

    const stored = recordSubmittedAction(null, envelope(), "action", mainHash, push, storage)

    expect(stored.transaction_hash).toBe(mainHash)
    expect(push).toHaveBeenCalledWith({
      action_id: "action",
      phase: "action",
      transaction_hash: mainHash,
    })
  })

  it("switches to Base and then rechecks the chain", async () => {
    const chainId = vi.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(8453)
    const boundary = clients({chainId, allowance: vi.fn(async () => 2_000_000_000_000_000_000n)})

    await executePreparedStakingAction(envelope(), provider, boundary)

    expect(boundary.switchToBase).toHaveBeenCalledOnce()
    expect(chainId).toHaveBeenCalledTimes(2)
  })

  it("fails closed on signer, chain, stale envelope, calldata, target and reverted receipt", async () => {
    await expect(
      executePreparedStakingAction(
        envelope(),
        provider,
        clients({
          addresses: vi.fn(async () => [
            "0x2222222222222222222222222222222222222222" as Address,
          ]),
        }),
      ),
    ).rejects.toThrow("connected wallet")

    await expect(
      executePreparedStakingAction(envelope(), provider, clients({chainId: vi.fn(async () => 1)})),
    ).rejects.toThrow("Switch to Base")

    await expect(
      executePreparedStakingAction(envelope({expires_at: new Date(0).toISOString()}), provider, clients()),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(envelope({data: "0xdeadbeef"}), provider, clients()),
    ).rejects.toThrow("data changed")

    const changedAmount = 2_000_000_000_000_000_000n
    const changedData = encodeFunctionData({
      abi: parseAbi(["function stake(uint256 amount,address receiver)"]),
      functionName: "stake",
      args: [changedAmount, wallet],
    })
    await expect(
      executePreparedStakingAction(
        envelope({data: changedData, arguments: {amount_atomic: changedAmount.toString(), receiver: wallet}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("approval changed")

    await expect(
      executePreparedStakingAction(
        envelope({arguments: {amount_atomic: "1500000000000000000", receiver: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("recipient changed")

    await expect(
      executePreparedStakingAction(envelope({expires_at: "not-a-date"}), provider, clients()),
    ).rejects.toThrow("expired")

    await expect(
      executePreparedStakingAction(
        envelope({to: "0x2222222222222222222222222222222222222222"}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("target changed")

    const badApproval = envelope().approval!
    await expect(
      executePreparedStakingAction(
        envelope({approval: {...badApproval, spender: "0x2222222222222222222222222222222222222222"}}),
        provider,
        clients(),
      ),
    ).rejects.toThrow("approval changed")

    await expect(
      executePreparedStakingAction(
        envelope({approval: null}),
        provider,
        clients({receipt: vi.fn(async () => ({status: "reverted" as const}))}),
      ),
    ).rejects.toThrow("staking transaction was reverted")
  })
})
