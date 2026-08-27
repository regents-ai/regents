import {describe, expect, it, vi} from "vitest"
import {encodeFunctionData, parseAbi, type Address, type Hash} from "viem"
import {executePreparedStakingAction, type PreparedStakingAction, type StakingClients} from "../js/wallet_actions/staking"

const wallet = "0x1111111111111111111111111111111111111111" as Address
const staking = "0xb027Dc261636E30Cbc0fE25b2F8e1ed273354AB5" as Address
const token = "0x6f89bcA4eA5931EdFCB09786267b251DeE752b07" as Address
const hash = `0x${"ab".repeat(32)}` as Hash
const amount = 1_500_000_000_000_000_000n
const provider = {request: vi.fn(async () => undefined)}

function envelope(approval = true): PreparedStakingAction {
  const data = encodeFunctionData({abi: parseAbi(["function stake(uint256 amount,address receiver)"]), functionName: "stake", args: [amount, wallet]})
  const approvalData = encodeFunctionData({abi: parseAbi(["function approve(address spender,uint256 amount)"]), functionName: "approve", args: [staking, amount]})
  return {action_id: crypto.randomUUID(), idempotency_key: "", confirmation_token: "signed", resource: "regent_staking", action: "stake", chain_id: 8453, to: staking, value: "0", data, expected_signer: wallet, prepared_at: new Date().toISOString(), expires_at: new Date(Date.now() + 60_000).toISOString(), risk_copy: "Stake", arguments: {amount_atomic: amount.toString(), receiver: wallet}, approval: approval ? {token, spender: staking, amount: amount.toString(), data: approvalData, mode: "exact"} : null}
}

function clients(allowance: bigint): StakingClients {
  return {addresses: vi.fn(async () => [wallet]), chainId: vi.fn(async () => 8453), switchToBase: vi.fn(), allowance: vi.fn(async () => allowance), simulate: vi.fn(), send: vi.fn(async () => hash)}
}

describe("direct staking wallet action", () => {
  it("asks only for Stake when allowance is sufficient", async () => {
    const prepared = envelope(false); prepared.idempotency_key = prepared.action_id
    const rpc = clients(amount)
    await executePreparedStakingAction(prepared, provider, rpc)
    expect(rpc.send).toHaveBeenCalledTimes(1)
    expect(rpc.send).toHaveBeenCalledWith(expect.objectContaining({to: staking}))
  })

  it("asks for exact approval then Stake without a receipt or allowance wait", async () => {
    const prepared = envelope(true); prepared.idempotency_key = prepared.action_id
    const rpc = clients(0n)
    await executePreparedStakingAction(prepared, provider, rpc)
    expect(rpc.send).toHaveBeenCalledTimes(2)
    expect(vi.mocked(rpc.send).mock.calls.map(([request]) => request.to)).toEqual([token, staking])
    expect(rpc.allowance).toHaveBeenCalledTimes(1)
  })

  it("refuses a changed signer before any wallet send", async () => {
    const prepared = envelope(false); prepared.idempotency_key = prepared.action_id
    const rpc = clients(amount); vi.mocked(rpc.addresses).mockResolvedValue(["0x2222222222222222222222222222222222222222"])
    await expect(executePreparedStakingAction(prepared, provider, rpc)).rejects.toThrow()
    expect(rpc.send).not.toHaveBeenCalled()
  })
})
