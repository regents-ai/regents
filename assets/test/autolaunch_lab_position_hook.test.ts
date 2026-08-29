import {getAddress, type Hex} from "viem"
import {afterEach, describe, expect, it, vi} from "vitest"

import {AutolaunchLabPosition} from "../js/hooks/autolaunch_lab_position"
import {replaceActiveEthereumWallet} from "../js/wallet_actions/connected_wallet"
import type {LabPositionOperation} from "../js/wallet_actions/autolaunch_lab_position"

const wallet = getAddress("0x1111111111111111111111111111111111111111")
const manager = getAddress("0x2222222222222222222222222222222222222222")
const hash = `0x${"ab".repeat(32)}`
const secondHash = `0x${"cd".repeat(32)}`
const blockHash = `0x${"12".repeat(32)}` as `0x${string}`

function operation(actionId = "lab-position"): LabPositionOperation {
  return {
    action_id: actionId,
    signer: wallet,
    chain_id: 31_337,
    lab: {
      rpc_url: "http://127.0.0.1:8545",
      chain_id: 31_337,
      addresses: {position_manager: manager.toLowerCase()},
    },
    lab_anchor: {block_number: 123, block_hash: blockHash},
    terminal: false,
    steps: [{step: "mint", to: manager, data: "0x1234" as Hex}],
  }
}

afterEach(() => {
  replaceActiveEthereumWallet(null)
  vi.unstubAllGlobals()
})

describe("the local position hook follows the LiveView event contract", () => {
  it("reacquires the selected provider and sends independent actions without persistence", async () => {
    vi.stubGlobal("window", {
      location: {origin: "https://regents.test"},
      dispatchEvent: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })
    const methods: string[] = []
    let sends = 0
    const provider = {
      request: vi.fn(async ({method}: {method: string}) => {
        methods.push(method)
        if (method === "eth_accounts") return [wallet]
        if (method === "eth_chainId") return "0x7a69"
        if (method === "eth_getBlockByNumber") return {hash: blockHash}
        if (method === "eth_sendTransaction") return sends++ === 0 ? hash : secondHash
        throw new Error(`Unexpected provider method ${method}`)
      }),
    }
    replaceActiveEthereumWallet({address: wallet, provider})

    const handlers = new Map<string, (payload: unknown) => unknown>()
    const pushed: Array<[string, unknown]> = []
    const hook = {
      el: {addEventListener: vi.fn()},
      handleEvent: (event: string, handler: (payload: unknown) => unknown) =>
        handlers.set(event, handler),
      pushEventTo: (_target: unknown, event: string, payload: unknown) =>
        pushed.push([event, payload]),
    }

    AutolaunchLabPosition.mounted?.call(hook)
    expect([...handlers.keys()].sort()).toEqual([
      "autolaunch-lab-position:cleared",
      "autolaunch-lab-position:operation",
      "autolaunch-lab-position:send",
    ])

    handlers.get("autolaunch-lab-position:operation")?.(operation())
    await handlers.get("autolaunch-lab-position:send")?.({
      action_id: "lab-position",
      step: "mint",
    })

    handlers.get("autolaunch-lab-position:operation")?.(operation("next-position"))
    await handlers.get("autolaunch-lab-position:send")?.({
      action_id: "next-position",
      step: "mint",
    })

    expect(methods).toEqual([
      "eth_accounts",
      "eth_chainId",
      "eth_getBlockByNumber",
      "eth_accounts",
      "eth_chainId",
      "eth_sendTransaction",
      "eth_accounts",
      "eth_chainId",
      "eth_getBlockByNumber",
      "eth_accounts",
      "eth_chainId",
      "eth_sendTransaction",
    ])
    expect(pushed).toContainEqual([
      "lab_position_submitted",
      {action_id: "lab-position", step: "mint", transaction_hash: hash},
    ])
    expect(pushed).toContainEqual([
      "lab_position_submitted",
      {action_id: "next-position", step: "mint", transaction_hash: secondHash},
    ])
  })
})
