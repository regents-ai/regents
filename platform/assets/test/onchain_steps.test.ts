import {afterEach, beforeEach, describe, expect, it, vi} from "vitest"

import {formInputs, OnchainSteps, press, type Review} from "../js/hooks/onchain_steps"
import {
  replaceActiveEthereumWallet,
  replaceConnectedEthereumWallets,
  type EthereumProvider,
} from "../js/wallet_actions/connected_wallet"

const signer = "0x1111111111111111111111111111111111111111"
const hash = `0x${"ab".repeat(32)}`
const inputs = {action: "stake", amount: "5", for_other: "false", receiver: ""}

const review: Review = {
  id: "review-1",
  component_id: "staking-actions",
  signer,
  chain: {chain_id: 8453, name: "Base", rpc_url: "https://mainnet.base.org"},
  steps: [
    {kind: "transaction", step: "approve", to: "0x2222222222222222222222222222222222222222", data: "0x095ea7b3", value: "0x0"},
    {kind: "transaction", step: "stake", to: "0x3333333333333333333333333333333333333333", data: "0x7acb7757", value: "0x0"},
    {kind: "transaction", step: "claim_usdc", to: "0x3333333333333333333333333333333333333333", data: "0xaaaaaaaa", value: "0x0"},
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

const sent = (step: string) => ["step_sent", {review_id: review.id, step, transaction_hash: hash}]

let pushed: Array<[string, unknown]>
const push = async (event: string, payload: unknown) => void pushed.push([event, payload])
const dispatched: string[] = []

// A form field as the hook reads it: text by value, a box by whether it is ticked.
class FakeInput {
  type: string
  value = ""
  checked = false
  dataset: Record<string, string>

  constructor(name: string, type = "text") {
    this.type = type
    this.dataset = {onchainInput: name}
  }
}

beforeEach(() => {
  pushed = []
  dispatched.length = 0
  vi.stubGlobal("HTMLInputElement", FakeInput)
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

describe("a press on a wallet button", () => {
  it("reaches the wallet every time, even while the first is still there", async () => {
    const {provider, sends} = wallet()

    const first = press(review, "approve", push)
    const second = press(review, "approve", push)
    await vi.waitFor(() => expect(sends).toHaveLength(2))

    sends.forEach(send => send(hash))
    await Promise.all([first, second])
    expect(methods(provider).filter(m => m === "eth_sendTransaction")).toHaveLength(2)
    expect(pushed).toEqual([sent("approve"), sent("approve")])
  })

  it("sends exactly the step the server built, and reads the chain last", async () => {
    const {provider, sends} = wallet()
    const sending = press(review, "stake", push)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    sends[0](hash)
    await sending

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

  it("says the wallet has too little for the fee when it refuses for that", async () => {
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

  it("sends nothing when Privy's active wallet is not the review's signer", async () => {
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

    const sending = press(review, "stake", push)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    sends[0](hash)
    await sending
    expect(methods(provider)).toContain("wallet_addEthereumChain")
    expect(pushed).toEqual([sent("stake")])
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

// The component: its form fields, a primary button that depends on them, and a claim button.
function page(form: Record<string, string>) {
  const fields = {
    action: Object.assign(new FakeInput("action", "hidden"), {value: form.action}),
    amount: Object.assign(new FakeInput("amount"), {value: form.amount}),
    for_other: Object.assign(new FakeInput("for_other", "checkbox"), {checked: form.for_other === "true"}),
    receiver: Object.assign(new FakeInput("receiver"), {value: form.receiver}),
  }
  let clicked: (event: Event) => void = () => {}
  const button = (dataset: Record<string, string>) => {
    const element = {dataset: {...dataset}} as unknown as HTMLElement & {closest: (selector: string) => HTMLElement | null}
    // Answers "[data-onchain-step]" and the like by the button's own data attributes.
    element.closest = (selector: string) => {
      const name = selector.slice(6, -1).replace(/-(\w)/g, (_match: string, letter: string) => letter.toUpperCase())
      return name in element.dataset ? element : null
    }
    return element
  }
  const el = {
    id: "staking-actions",
    contains: () => true,
    hasAttribute: () => false,
    querySelectorAll: () => Object.values(fields),
    querySelector: () => null,
    addEventListener: (_type: string, listener: (event: Event) => void) => { clicked = listener },
    removeEventListener: () => {},
  } as unknown as HTMLElement

  const primary = button({onchainStep: "stake"})
  const claim = button({onchainStep: "claim_usdc"})
  return {el, fields, primary, claim, click: (target: HTMLElement) => clicked({target} as unknown as Event)}
}

function mount(form: Record<string, string>) {
  const events: Record<string, (payload: unknown) => void> = {}
  // The server's replies, in the order the pushes that asked for them were made.
  const replies: Array<{resolve: (reply: unknown) => void; reject: (error: unknown) => void}> = []
  const view = page(form)
  const hook = {
    el: view.el,
    handleEvent: (event: string, callback: (payload: unknown) => void) => { events[event] = callback },
    pushEventTo: (_target: HTMLElement, event: string, payload: unknown) => {
      push(event, payload)
      return new Promise((resolve, reject) =>
        replies.push({resolve: reply => resolve([{status: "fulfilled", value: {reply}}]), reject}))
    },
  }
  ;(OnchainSteps.mounted as (this: typeof hook) => void).call(hook)
  pushed = []
  replies.length = 0
  return {
    ...view,
    replies,
    review: (payload: Review) => events["onchain-steps:review"]({component_id: payload.component_id, review: payload}),
  }
}

describe("the wallet-button hook", () => {
  it("sends at once when the review matches the form", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)

    view.click(view.primary)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    expect(view.primary.dataset.awaitingWallet).toBe("true")
    sends[0](hash)
    await vi.waitFor(() => expect(pushed).toEqual([sent("stake")]))
    // The words stay on the wallet until the page shows the server's answer.
    expect(view.primary.dataset.awaitingWallet).toBe("true")
    view.replies[0].resolve({})
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
  })

  it("asks for the matching review when the form changed, and sends what comes back", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)
    view.fields.amount.value = "7"

    view.click(view.primary)
    view.click(view.primary)
    expect(sends).toHaveLength(0)
    expect(pushed).toEqual([
      ["prepare_and_send", {form: {...inputs, amount: "7"}, step: "stake"}],
      ["prepare_and_send", {form: {...inputs, amount: "7"}, step: "stake"}],
    ])
    expect(view.primary.dataset.awaitingWallet).toBe("true")

    const rebuilt = {...review, id: "review-2", inputs: {...inputs, amount: "7"}}
    view.replies.forEach(({resolve}) => resolve({review: rebuilt, send: "stake"}))
    await vi.waitFor(() => expect(sends).toHaveLength(2))
    sends.forEach(send => send(hash))
    await vi.waitFor(() => expect(view.replies).toHaveLength(4))
    view.replies.slice(2).forEach(({resolve}) => resolve({}))
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
    const sentRebuilt = ["step_sent", {review_id: "review-2", step: "stake", transaction_hash: hash}]
    expect(pushed.slice(2)).toEqual([sentRebuilt, sentRebuilt])
  })

  it("gives the button back when the question is lost or the server has nothing to send", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)
    view.fields.amount.value = "7"

    view.click(view.primary)
    view.click(view.primary)
    view.replies[0].reject(new Error("disconnected"))
    view.replies[1].resolve({})
    await vi.waitFor(() => expect(view.replies).toHaveLength(3))
    view.replies[2].resolve({})
    await vi.waitFor(() => expect(view.primary.dataset.awaitingWallet).toBeUndefined())
    expect(sends).toHaveLength(0)
    expect(pushed.slice(2)).toEqual([["step_failed", {step: "stake", reason: "step_unknown"}]])
  })

  it("asks for a review when pressed before the first one arrives", async () => {
    const {sends} = wallet()
    const view = mount(inputs)

    view.click(view.primary)
    expect(pushed).toEqual([["prepare_and_send", {form: inputs, step: "stake"}]])
    view.replies[0].resolve({review, send: "stake"})
    await vi.waitFor(() => expect(sends).toHaveLength(1))
  })

  it("opens the connect step at once when no wallet is active, whatever the form says", async () => {
    const view = mount(inputs)
    view.review(review)
    view.fields.amount.value = "7"

    view.click(view.primary)
    await vi.waitFor(() => expect(pushed).toEqual([["step_failed", {step: "stake", reason: "wallet_unavailable"}]]))
    expect(dispatched).toContain("ash:wallet-connect")
  })

  it("sends a claim at once while the form matches", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review(review)

    view.click(view.claim)
    await vi.waitFor(() => expect(sends).toHaveLength(1))
    expect(pushed).toEqual([])
  })

  it("keeps only this component's review", async () => {
    const {sends} = wallet()
    const view = mount(inputs)
    view.review({...review, component_id: "another-panel"})

    view.click(view.claim)
    expect(pushed).toEqual([["prepare_and_send", {form: inputs, step: "claim_usdc"}]])
    expect(sends).toHaveLength(0)
  })

  it("reads text as typed and boxes as true or false", () => {
    const {el, fields} = page(inputs)
    expect(formInputs(el)).toEqual(inputs)
    fields.for_other.checked = true
    expect(formInputs(el)).toEqual({...inputs, for_other: "true"})
  })

  it("reads a group of choices as the one chosen", () => {
    const base = Object.assign(new FakeInput("chain", "radio"), {value: "base", checked: true})
    const ethereum = Object.assign(new FakeInput("chain", "radio"), {value: "ethereum"})
    const el = {querySelectorAll: () => [base, ethereum]} as unknown as HTMLElement
    expect(formInputs(el)).toEqual({chain: "base"})
    base.checked = false
    ethereum.checked = true
    expect(formInputs(el)).toEqual({chain: "ethereum"})
  })
})
