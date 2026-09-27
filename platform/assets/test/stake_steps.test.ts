import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import {formInputs, press, StakeSteps, type Inputs, type Review} from "../js/hooks/stake_steps"
import {
  replaceActiveEthereumWallet,
  replaceConnectedEthereumWallets,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const signer = "0x1111111111111111111111111111111111111111"
const hash = `0x${"ab".repeat(32)}`
const inputs: Inputs = {action: "stake", amount: "5", for_other: false, receiver: "", acknowledged: false}

const review: Review = {
  component_id: "regent-staking",
  signer,
  chain: {chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"},
  steps: [
    {step: "approve", to: "0x2222222222222222222222222222222222222222", data: "0x095ea7b3", value: "0x0"},
    {step: "stake", to: "0x3333333333333333333333333333333333333333", data: "0x7acb7757", value: "0x0"},
  ],
  inputs,
}

// A stand-in wallet Privy has active: answers by method name, and holds every send until released.
function wallet(answers: Record<string, unknown> = {}, address = signer) {
  const sends: Array<(value: unknown) => void> = []
  const provider: EthereumProvider = {
    request: vi.fn(async ({method}) => {
      if (method === "eth_sendTransaction") return new Promise(resolve => sends.push(resolve))
      const answer = ({eth_chainId: "0x2105", eth_accounts: [signer], ...answers} as Record<string, unknown>)[method]
      if (answer instanceof Error) throw answer
      return answer
    }),
  }
  replaceConnectedEthereumWallets([[address, {provider, disconnect: () => {}}]])
  replaceActiveEthereumWallet({address, provider})
  return {provider, sends}
}

const methods = (provider: EthereumProvider) =>
  vi.mocked(provider.request).mock.calls.map(([{method}]) => method)

let pushed: Array<[string, unknown]>
const push = (event: string, payload: unknown) => void pushed.push([event, payload])
const dispatched: string[] = []

beforeEach(() => {
  pushed = []
  dispatched.length = 0
  vi.stubGlobal("window", {
    location: {origin: "https://regents.sh"},
    localStorage: {getItem: () => null},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: (event: Event) => void dispatched.push(event.type),
  })
})

afterEach(() => {
  replaceConnectedEthereumWallets([])
  replaceActiveEthereumWallet(null)
  vi.unstubAllGlobals()
})

describe("a press on a Stake button", () => {
  it("reaches the wallet every time, even while the first is still there", async () => {
    const {provider, sends} = wallet()

    const first = press(review, "approve", push)
    const second = press(review, "approve", push)
    await vi.waitFor(() => expect(sends).toHaveLength(2))

    sends.forEach(send => send(hash))
    await Promise.all([first, second])
    expect(methods(provider).filter(m => m === "eth_sendTransaction")).toHaveLength(2)
    expect(pushed).toEqual([
      ["step_sent", {step: "approve", transaction_hash: hash, data: "0x095ea7b3", from: signer}],
      ["step_sent", {step: "approve", transaction_hash: hash, data: "0x095ea7b3", from: signer}],
    ])
  })

  it("sends exactly the step the server built, and reads the chain last", async () => {
    const {provider, sends} = wallet()
    const sent = press(review, "stake", push)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    sends[0](hash)
    await sent

    expect(methods(provider).slice(-2)).toEqual(["eth_chainId", "eth_sendTransaction"])
    expect(vi.mocked(provider.request).mock.calls.at(-1)?.[0].params).toEqual([{
      from: signer,
      to: "0x3333333333333333333333333333333333333333",
      data: "0x7acb7757",
      value: "0x0",
    }])
  })

  it("reports a decline", async () => {
    const {provider} = wallet()
    vi.mocked(provider.request).mockImplementation(async ({method}) => {
      if (method === "eth_sendTransaction") throw Object.assign(new Error("no"), {code: 4001})
      return ({eth_chainId: "0x2105", eth_accounts: [signer]} as Record<string, unknown>)[method]
    })
    await press(review, "stake", push)
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_declined"}]])
  })

  it("says the wallet may have sent it when the send fails after it began", async () => {
    const {provider} = wallet()
    vi.mocked(provider.request).mockImplementation(async ({method}) => {
      if (method === "eth_sendTransaction") throw new Error("lost")
      return ({eth_chainId: "0x2105", eth_accounts: [signer]} as Record<string, unknown>)[method]
    })
    await press(review, "stake", push)
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "send_unconfirmed"}]])
  })

  it("says the wallet has no ETH for the fee when it refuses for that", async () => {
    const {provider} = wallet()
    vi.mocked(provider.request).mockImplementation(async ({method}) => {
      if (method === "eth_sendTransaction") {
        throw new Error("request failed", {cause: new Error("insufficient funds for gas * price + value")})
      }
      return ({eth_chainId: "0x2105", eth_accounts: [signer]} as Record<string, unknown>)[method]
    })
    await press(review, "stake", push)
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "insufficient_funds"}]])
  })

  it("sends nothing when Privy's active wallet is not the one the page shows", async () => {
    const {provider} = wallet({}, "0x4444444444444444444444444444444444444444")
    await press(review, "stake", push)
    expect(methods(provider)).toEqual([])
    expect(dispatched).toEqual([])
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_unavailable"}]])
  })

  it("sends nothing when the wallet app answers for another account", async () => {
    const {provider} = wallet({eth_accounts: ["0x4444444444444444444444444444444444444444"]})
    await press(review, "stake", push)
    expect(methods(provider)).not.toContain("eth_sendTransaction")
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_unavailable"}]])
  })

  it("moves the wallet to Base, adding it when the wallet does not know it", async () => {
    let chain = "0x1"
    const {provider, sends} = wallet()
    vi.mocked(provider.request).mockImplementation(async ({method}) => {
      if (method === "wallet_switchEthereumChain" && chain === "0x1") {
        chain = "unknown"
        throw Object.assign(new Error("unknown chain"), {code: 4902})
      }
      if (method === "wallet_switchEthereumChain") chain = "0x2105"
      if (method === "eth_sendTransaction") return new Promise(resolve => sends.push(resolve))
      return ({eth_chainId: chain === "0x2105" ? "0x2105" : "0x1", eth_accounts: [signer]} as Record<string, unknown>)[method]
    })

    const sent = press(review, "stake", push)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    sends[0](hash)
    await sent
    expect(methods(provider)).toContain("wallet_addEthereumChain")
    expect(pushed).toEqual([["step_sent", {step: "stake", transaction_hash: hash, data: "0x7acb7757", from: signer}]])
  })

  it("sends nothing when the wallet will not switch to Base", async () => {
    const {provider} = wallet({
      eth_chainId: "0x1",
      wallet_switchEthereumChain: Object.assign(new Error("no"), {code: 4001}),
    })
    await press(review, "stake", push)
    expect(methods(provider)).not.toContain("eth_sendTransaction")
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "network_mismatch"}]])
  })

  it("opens the connect step when no wallet is active here", async () => {
    await press(review, "stake", push)
    expect(dispatched).toEqual(["ash:wallet-connect"])
    expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_unavailable"}]])
  })

  it("says the page has no such step rather than sending one of its own", async () => {
    const {provider} = wallet()
    await press(undefined, "stake", push)
    await press(review, "unstake", push)
    expect(methods(provider)).not.toContain("eth_sendTransaction")
    expect(pushed).toEqual([
      ["step_failed", {step: "stake", reason: "step_unknown"}],
      ["step_failed", {step: "unstake", reason: "step_unknown"}],
    ])
  })
})

// The page: a form, a primary button that depends on it, and a claim button that does not.
function page(form: Inputs) {
  const fields: Record<string, {value?: string; checked?: boolean}> = {
    "staking-amount": {value: form.amount},
    "staking-for-other": {checked: form.for_other},
    "staking-recipient": {value: form.receiver},
    "staking-recipient-acknowledged": {checked: form.acknowledged},
  }
  let clicked: (event: Event) => void = () => {}
  const button = (dataset: Record<string, string>) => {
    const element = {dataset: {...dataset}} as unknown as HTMLElement & {closest: () => HTMLElement}
    element.closest = () => element
    return element
  }
  const el = {
    id: "regent-staking",
    dataset: {stakingMode: form.action},
    querySelector: (selector: string) => fields[selector.slice(1)] ?? null,
    addEventListener: (_type: string, listener: (event: Event) => void) => { clicked = listener },
    removeEventListener: () => {},
  } as unknown as HTMLElement

  const primary = button({onchainStep: "stake", onchainForm: "staking-amount-form"})
  const claim = button({onchainStep: "claim_usdc"})
  return {el, fields, primary, claim, click: (target: HTMLElement) => clicked({target} as unknown as Event)}
}

function mount(form: Inputs) {
  const events: Record<string, (payload: unknown) => void> = {}
  // The server's replies, in the order the pushes that asked for them were made.
  const replies: Array<{resolve: (reply: unknown) => void; reject: (error: unknown) => void}> = []
  const view = page(form)
  const hook = {
    el: view.el,
    handleEvent: (event: string, callback: (payload: unknown) => void) => { events[event] = callback },
    pushEvent: (event: string, payload: unknown) => {
      push(event, payload)
      return new Promise((resolve, reject) => replies.push({resolve, reject}))
    },
  }
  ;(StakeSteps.mounted as (this: typeof hook) => void).call(hook)
  pushed = []
  replies.length = 0
  return {...view, replies, review: (payload: unknown) => events["onchain-steps:review"](payload)}
}

describe("the Stake page hook", () => {
  it("sends at once when the review matches the form", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)

    view.click(view.primary)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    expect(view.primary.dataset.awaitingWallet).toBe("true")
    sends[0](hash)
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
    expect(pushed).toEqual([["step_sent", {step: "stake", transaction_hash: hash, data: "0x7acb7757", from: signer}]])
  })

  it("asks for the matching step when the form changed, and sends what comes back", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)
    view.fields["staking-amount"].value = "7"

    view.click(view.primary)
    view.click(view.primary)
    expect(sends).toHaveLength(0)
    expect(pushed).toEqual([
      ["prepare_and_send", {form: {...inputs, amount: "7"}}],
      ["prepare_and_send", {form: {...inputs, amount: "7"}}],
    ])
    expect(view.primary.dataset.awaitingWallet).toBe("true")

    const rebuilt = {...review, inputs: {...inputs, amount: "7"}}
    view.replies.forEach(({resolve}) => resolve({review: rebuilt, send: "stake"}))
    await vi.waitFor(() => expect(sends).toHaveLength(2))
    sends.forEach(send => send(hash))
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
    expect(pushed.slice(2)).toEqual([
      ["step_sent", {step: "stake", transaction_hash: hash, data: "0x7acb7757", from: signer}],
      ["step_sent", {step: "stake", transaction_hash: hash, data: "0x7acb7757", from: signer}],
    ])
  })

  it("gives the button back when the question is lost or the server has nothing to send", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)
    view.fields["staking-amount"].value = "7"

    view.click(view.primary)
    view.click(view.primary)
    view.replies[0].reject(new Error("disconnected"))
    view.replies[1].resolve({})
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
    expect(sends).toHaveLength(0)
  })

  it("opens the connect step at once when no wallet is active, whatever the form says", async () => {
    const view = mount(inputs)
    view.review(review)
    view.fields["staking-amount"].value = "7"

    view.click(view.primary)
    await vi.waitFor(() => expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_unavailable"}]]))
    expect(dispatched).toContain("ash:wallet-connect")
  })

  it("sends a claim whatever is typed in the form", async () => {
    const claimReview = {...review, steps: [...review.steps, {step: "claim_usdc", to: signer, data: "0xaaaaaaaa", value: "0x0"}]}
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(claimReview)
    view.fields["staking-amount"].value = "9"

    view.click(view.claim)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    expect(pushed).toEqual([])
  })

  it("keeps only this page's review", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review({...review, component_id: "another-panel"})

    view.click(view.claim)
    await vi.waitFor(() => expect(pushed).toEqual([["step_failed", {step: "claim_usdc", reason: "step_unknown"}]]))
    expect(sends).toHaveLength(0)
  })

  it("reads the acknowledgment only while staking for someone else", () => {
    const {el, fields} = page({...inputs, for_other: false, acknowledged: true})
    expect(formInputs(el).acknowledged).toBe(false)
    fields["staking-for-other"].checked = true
    expect(formInputs(el)).toEqual({...inputs, for_other: true, acknowledged: true})
  })
})
