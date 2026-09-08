import {afterEach, expect, it, vi} from "vitest"
import {PrivyShowcase} from "../js/hooks/privy_showcase"

const selection = vi.hoisted(() => ({current: null as {address: string} | null}))
vi.mock("../js/wallet_actions/connected_wallet", () => ({activeEthereumWallet: () => selection.current}))
afterEach(() => { selection.current = null; vi.unstubAllGlobals() })

it("observes the existing wallet store and removes its listener on teardown", () => {
  const events = new EventTarget()
  vi.stubGlobal("window", events)
  const sync = vi.fn()
  events.addEventListener("ash:wallet-sync", sync)
  const hook = {
    el: {dataset: {privyEnabled: "true"}},
    pushEvent: vi.fn(),
    cleanup: undefined as (() => void) | undefined,
  }
  PrivyShowcase.mounted?.call(hook)
  expect(sync).toHaveBeenCalledOnce()
  expect(hook.pushEvent).toHaveBeenLastCalledWith("privy_wallet_changed", {address: null})
  selection.current = {address: "0x1111111111111111111111111111111111111111"}
  events.dispatchEvent(new Event("ash:wallet-state"))
  expect(hook.pushEvent).toHaveBeenLastCalledWith("privy_wallet_changed", selection.current)
  selection.current = null
  events.dispatchEvent(new Event("ash:wallet-state"))
  expect(hook.pushEvent).toHaveBeenLastCalledWith("privy_wallet_changed", {address: null})
  PrivyShowcase.destroyed?.call(hook)
  hook.pushEvent.mockClear()
  events.dispatchEvent(new Event("ash:wallet-state"))
  expect(hook.pushEvent).not.toHaveBeenCalled()
})

it("does not bootstrap Privy on a fixture or unconfigured reference page", () => {
  const events = new EventTarget()
  vi.stubGlobal("window", events)
  const sync = vi.fn()
  events.addEventListener("ash:wallet-sync", sync)
  const hook = {el: {dataset: {privyEnabled: "false"}}, pushEvent: vi.fn(), cleanup: undefined as (() => void) | undefined}
  PrivyShowcase.mounted?.call(hook)
  expect(sync).not.toHaveBeenCalled()
  PrivyShowcase.destroyed?.call(hook)
})
