import {getAddress, type Hash, type Hex} from "viem"
import {describe, expect, it, vi} from "vitest"

import {
  sendLabPositionStep,
  sendableLabPositionStep,
  type LabPositionOperation,
} from "../js/wallet_actions/autolaunch_lab_position"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const manager = getAddress("0x2222222222222222222222222222222222222222")
const hash = `0x${"cd".repeat(32)}` as Hash
const blockHash = `0x${"12".repeat(32)}` as Hash

function operation(overrides: Partial<LabPositionOperation> = {}): LabPositionOperation {
  return {
    action_id: "lab-position",
    signer: wallet,
    chain_id: 31_337,
    lab: {
      run_id: "acceptance-run-1",
      rpc_url: "http://127.0.0.1:8545",
      chain_id: 31_337,
      addresses: {position_manager: manager.toLowerCase()},
    },
    lab_anchor: {block_number: 123, block_hash: blockHash},
    terminal: false,
    steps: [{step: "mint", to: manager, data: "0x1234" as Hex}],
    ...overrides,
  }
}

describe("a local position sends only its reviewed lab step", () => {
  it("refuses Base, a different operation, terminal work and changed bytes", () => {
    expect(() =>
      sendableLabPositionStep(operation({chain_id: 8453, lab: null}), "lab-position", "mint"),
    ).toThrow("lab position cannot be sent to Base")
    expect(() => sendableLabPositionStep(operation(), "other", "mint")).toThrow(
      "different lab position",
    )
    expect(() =>
      sendableLabPositionStep(operation({terminal: true}), "lab-position", "mint"),
    ).toThrow("already finished")
    expect(() =>
      sendableLabPositionStep(
        operation({steps: [{step: "mint", to: manager, data: "0xABCD" as Hex}]}),
        "lab-position",
        "mint",
      ),
    ).toThrow("reviewed transaction changed")
  })

  it("uses the shared final-chain guard and sends zero local value", async () => {
    const methods: string[] = []
    const provider = {
      request: vi.fn(async ({method, params}: {method: string; params?: unknown[]}) => {
        methods.push(method)
        if (method === "eth_chainId") return "0x7a69"
        if (method === "eth_accounts") return [wallet]
        if (method === "eth_getBlockByNumber") return {hash: blockHash}
        if (method === "eth_sendTransaction") {
          expect(params).toEqual([
            {from: wallet, to: manager, data: "0x1234", value: "0x0"},
          ])
          return hash
        }
        throw new Error(`Unexpected provider method ${method}`)
      }),
    }
    const held = operation()

    await expect(
      sendLabPositionStep(
        held,
        sendableLabPositionStep(held, "lab-position", "mint"),
        () => ({address: wallet, provider}),
        vi.fn(),
      ),
    ).resolves.toBe(hash)
    expect(methods.slice(-2)).toEqual(["eth_chainId", "eth_sendTransaction"])
  })
})
