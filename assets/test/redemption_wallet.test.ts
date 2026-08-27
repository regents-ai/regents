import {describe, expect, it, vi} from "vitest"
import {encodeFunctionData, getAddress, type Hash} from "viem"
import chainManifest from "../../contracts/base-mainnet.json"
import redeemerAbiJson from "../../contracts/abi/animata-redeemer.json"
import {executePreparedRedemptionAction, type PreparedRedemptionAction, type RedemptionClients} from "../js/wallet_actions/redemption"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const redeemer = getAddress(chainManifest.contracts.animata_redeemer.address)
const hash = `0x${"ab".repeat(32)}` as Hash
const provider = {request: vi.fn(async () => undefined)}

function envelope(): PreparedRedemptionAction {
  return {action_id: crypto.randomUUID(), idempotency_key: "", confirmation_token: "signed", resource: "animata_redemption", action: "claim", chain_id: 8453, to: redeemer, value: "0", data: encodeFunctionData({abi: redeemerAbiJson, functionName: "claim"}), expected_signer: wallet, prepared_at: new Date().toISOString(), expires_at: new Date(Date.now() + 60_000).toISOString(), risk_copy: "Claim", arguments: {}}
}
function clients(): RedemptionClients { return {addresses: vi.fn(async () => [wallet]), chainId: vi.fn(async () => 8453), switchToBase: vi.fn(), simulate: vi.fn(), send: vi.fn(async () => hash)} }

describe("direct redemption wallet action", () => {
  it("sends one exact action and reports no browser result", async () => {
    const prepared = envelope(); prepared.idempotency_key = prepared.action_id
    const rpc = clients()
    await expect(executePreparedRedemptionAction(prepared, provider, rpc)).resolves.toBeUndefined()
    expect(rpc.send).toHaveBeenCalledOnce()
  })
  it("switches to Base and rechecks before sending", async () => {
    const prepared = envelope(); prepared.idempotency_key = prepared.action_id
    const rpc = clients(); vi.mocked(rpc.chainId).mockResolvedValueOnce(1).mockResolvedValueOnce(8453)
    await executePreparedRedemptionAction(prepared, provider, rpc)
    expect(rpc.switchToBase).toHaveBeenCalledOnce()
    expect(rpc.chainId).toHaveBeenCalledTimes(2)
  })
})
