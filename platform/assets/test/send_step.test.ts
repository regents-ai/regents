// Invariant: the send step compares addresses in any letter case without viem,
// so a wallet that answers its account checksummed still sends the server's step,
// and a wallet on another account sends nothing.
import {expect, it} from "vitest"

import {NothingSent, sendStep, type TransactionStep} from "../js/wallet_actions/send_step"

const chain = {chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"}
const step: TransactionStep = {
  kind: "transaction",
  step: "buy",
  to: "0x1111111111111111111111111111111111111111",
  data: "0x",
  value: "0x0",
}
const hash = `0x${"ab".repeat(32)}`

function walletOn(account: string) {
  const sent: unknown[] = []
  const provider = {
    request: async ({method, params}: {method: string; params?: unknown[]}) => {
      if (method === "eth_chainId") return "0x2105"
      if (method === "eth_accounts") return [account]
      if (method === "eth_sendTransaction") {
        sent.push(params?.[0])
        return hash
      }
      throw new Error(`unexpected ${method}`)
    },
  }
  return {sent, selected: {address: account, provider}}
}

it("sends when the wallet names the signer in other letter case", async () => {
  const checksummed = "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"
  const signer = checksummed.toLowerCase() as `0x${string}`
  const {sent, selected} = walletOn(checksummed)

  await expect(sendStep(chain, signer, step, () => selected, () => undefined)).resolves.toBe(hash)
  expect(sent).toEqual([{from: signer, to: step.to, data: "0x", value: "0x0", chainId: "0x2105"}])
})

it("sends nothing when the wallet answers for another account", async () => {
  const {sent, selected} = walletOn("0x2222222222222222222222222222222222222222")
  const signer = "0x3333333333333333333333333333333333333333"

  await expect(sendStep(chain, signer, step, () => selected, () => undefined)).rejects.toBeInstanceOf(NothingSent)
  expect(sent).toEqual([])
})
