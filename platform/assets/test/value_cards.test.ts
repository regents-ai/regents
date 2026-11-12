// The value cards' rules that hold whatever the panels show: every panel on a
// page draws on one device, the last to go gives it back, a lost device is told
// to everyone on it and never handed out again, and every panel a card can ask
// for has a still frame to stand in for it.
import {existsSync} from "node:fs"
import {fileURLToPath} from "node:url"
import {describe, expect, it, vi} from "vitest"
import {panels} from "../js/value_cards"
import {shareDevice} from "../js/value_cards/shared_device"

/** A device that can be lost on demand, and counts being given back. */
const fakeDevice = () => {
  let lose = () => {}
  const lost = new Promise<void>(resolve => (lose = resolve))
  return {lost, lose, dispose: vi.fn(() => lose())}
}

/** A page whose every request for a device hands out the next fake one. */
const page = () => {
  const made: ReturnType<typeof fakeDevice>[] = []
  const open = vi.fn(async () => {
    made.push(fakeDevice())
    return made.at(-1)!
  })
  return {made, open, ...shareDevice(open)}
}

describe("the shared device", () => {
  it("is asked for once, however many panels join while it is on its way", async () => {
    const {open, join} = page()
    const [first, second, third] = await Promise.all([join(() => {}), join(() => {}), join(() => {})])
    expect(open).toHaveBeenCalledTimes(1)
    expect(second).toBe(first)
    expect(third).toBe(first)
  })

  it("is given back by the last panel to leave, and asked for again by the next to join", async () => {
    const {made, open, join, leave} = page()
    const [one, two] = [() => {}, () => {}]
    const shared = await join(one)
    await join(two)
    leave(shared, one)
    expect(made[0]!.dispose).not.toHaveBeenCalled()
    leave(shared, two)
    expect(made[0]!.dispose).toHaveBeenCalledTimes(1)
    expect((await join(one)).gpu).toBe(made[1])
    expect(open).toHaveBeenCalledTimes(2)
  })

  it("tells every panel on it when it is lost, and is given back once they have all left", async () => {
    const {made, join, leave} = page()
    const [one, two] = [vi.fn(), vi.fn()]
    const shared = await join(one)
    await join(two)
    made[0]!.lose()
    await made[0]!.lost
    await Promise.resolve()
    expect(one).toHaveBeenCalledTimes(1)
    expect(two).toHaveBeenCalledTimes(1)
    leave(shared, one)
    leave(shared, two)
    expect(made[0]!.dispose).toHaveBeenCalledTimes(1)
  })

  it("never hands a lost device to the next panel to ask", async () => {
    const {made, join} = page()
    const first = await join(() => {})
    made[0]!.lose()
    await made[0]!.lost
    await Promise.resolve()
    const next = await join(() => {})
    expect(next).not.toBe(first)
    expect(next.gpu).toBe(made[1])
  })

  it("gives a panel the next device when the one it waited for was lost as it opened", async () => {
    const {made, open, join} = page()
    open.mockImplementationOnce(async () => {
      made.push(fakeDevice())
      made[0]!.lose()
      return made[0]!
    })
    const told = vi.fn()
    const shared = await join(told)
    expect(shared.gpu).toBe(made[1])
    expect(made[0]!.dispose).toHaveBeenCalledTimes(1)
    expect(told).not.toHaveBeenCalled()
  })

  it("stops asking after two devices in a row are lost as they open", async () => {
    const open = vi.fn(async () => {
      const device = fakeDevice()
      device.lose()
      return device
    })
    const {join} = shareDevice(open)
    await expect(join(() => {})).rejects.toThrow("lost as it opened")
    expect(open).toHaveBeenCalledTimes(2)
  })

  it("asks again after a device that never came", async () => {
    const device = fakeDevice()
    const open = vi.fn<() => Promise<typeof device>>().mockRejectedValueOnce(new Error("no adapter")).mockResolvedValue(device)
    const {join} = shareDevice(open)
    await expect(join(() => {})).rejects.toThrow("no adapter")
    expect((await join(() => {})).gpu).toBe(device)
  })
})

describe("every panel", () => {
  it.each(Object.keys(panels))("%s has a still frame", name => {
    const still = fileURLToPath(new URL(`../../priv/static/images/value-cards/${name}.webp`, import.meta.url))
    expect(existsSync(still)).toBe(true)
  })
})
