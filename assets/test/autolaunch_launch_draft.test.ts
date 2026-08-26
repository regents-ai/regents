import {describe, expect, it} from "vitest"

import {defaultedTreasury} from "../js/hooks/autolaunch_launch_draft"

const wallet = "0x1111111111111111111111111111111111111111"
const switched = "0x2222222222222222222222222222222222222222"
const typed = "0x9999999999999999999999999999999999999999"

describe("the connected wallet is a blank draft's ordinary Treasury default", () => {
  it("fills an empty field with the wallet Privy has selected", () => {
    expect(defaultedTreasury("", wallet, null)).toBe(wallet)
  })

  it("leaves the field blank when no Ethereum wallet is selected", () => {
    expect(defaultedTreasury("", null, null)).toBeNull()
  })

  it("never overwrites an address the customer entered", () => {
    expect(defaultedTreasury(typed, wallet, null)).toBeNull()
    expect(defaultedTreasury(typed, switched, wallet)).toBeNull()
  })

  it("refills the blank form a successful save leaves behind", () => {
    expect(defaultedTreasury("", wallet, wallet)).toBe(wallet)
  })

  it("follows a later wallet change only while the default is untouched", () => {
    expect(defaultedTreasury(wallet, switched, wallet)).toBe(switched)
  })

  it("writes nothing when the field already holds the selected wallet", () => {
    expect(defaultedTreasury(wallet, wallet, wallet)).toBeNull()
    expect(defaultedTreasury(wallet, wallet, null)).toBeNull()
  })
})
