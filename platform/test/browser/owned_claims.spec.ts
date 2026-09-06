import {test, expect} from "@playwright/test"
import {stripTypeScriptTypes} from "node:module"
import {readFileSync} from "node:fs"

let script: string
let styles: string

test.beforeAll(() => {
  script = stripTypeScriptTypes(readFileSync(new URL("../../assets/js/owned_claims.ts", import.meta.url), "utf8")) + "\nwindow.OwnedClaims = {mountOwnedClaims};"
  styles = readFileSync(new URL("../../assets/vendor/regent_ui/primitives.css", import.meta.url), "utf8")
    + readFileSync(new URL("../../assets/css/components/owned_claims.css", import.meta.url), "utf8")
    + "* { box-sizing: border-box; }"
})

test.beforeEach(async ({page}) => {
  await page.setContent(`<section id="names" class="rg-profile" data-owned-claims><button class="rg-button" data-claims-load>Load names</button><p role="status" data-claims-status></p><ul data-claims-list></ul><button class="rg-button" data-claims-more hidden>More names</button></section>`)
  await page.addStyleTag({content: styles})
  await page.addScriptTag({content: script, type: "module"})
  await page.evaluate(() => {
    const fixture = window as any
    fixture.requests = []
    fixture.stop = fixture.OwnedClaims.mountOwnedClaims(document.querySelector("#names"), (after, {signal}) => new Promise(resolve => fixture.requests.push({after, signal, resolve})))
  })
})

const deliver = async (page, index: number, name: string, next: string | null = null) => page.evaluate(({index, name, next}) => {
  (window as any).requests[index].resolve({ok: true, status: 200, body: {claims: [{id: String(index), name, owner_address: "0x" + "1".repeat(40), transaction: "0x" + "a".repeat(64), status: "Recorded", ens_name: null}], next}})
}, {index, name, next})

test("loads on demand, paginates, renders history as text, and clears on account change", async ({page}) => {
  expect(await page.evaluate(() => (window as any).requests.length)).toBe(0)
  await expect(page.getByRole("button", {name: "More names"})).toBeHidden()
  await page.getByRole("button", {name: "Load names", exact: true}).click()
  await deliver(page, 0, "<img src=x onerror=alert(1)>", "cursor-one")
  await expect(page.locator("li strong")).toHaveText("<img src=x onerror=alert(1)>")
  await expect(page.locator("li img")).toHaveCount(0)
  await page.getByRole("button", {name: "More names"}).click()
  expect(await page.evaluate(() => (window as any).requests[1].after)).toBe("cursor-one")
  await deliver(page, 1, "second.regent.eth")
  await expect(page.locator("li")).toHaveCount(2)
  await expect(page.getByRole("button", {name: "More names"})).toBeHidden()
  await page.evaluate(() => dispatchEvent(new Event("regent:profile-identity")))
  await expect(page.locator("li")).toHaveCount(0)
  expect(await page.evaluate(() => (window as any).requests.length)).toBe(2)
})

test("restarts a pending read on provider hydration and discards its obsolete response", async ({page}) => {
  await page.getByRole("button", {name: "Load names", exact: true}).click()
  await page.evaluate(() => dispatchEvent(new Event("regent:profile-identity")))
  expect(await page.evaluate(() => (window as any).requests[0].signal.aborted)).toBe(true)
  await deliver(page, 0, "old-person.regent.eth")
  await expect(page.locator("li")).toHaveCount(0)
  await deliver(page, 1, "current-person.regent.eth")
  await expect(page.locator("li strong")).toHaveText("current-person.regent.eth")
  await page.evaluate(() => dispatchEvent(new Event("pagehide")))
  await expect(page.locator("li")).toHaveCount(0)
})

test("a failed page can retry, and unmount prevents late data or further requests", async ({page}) => {
  await page.getByRole("button", {name: "Load names", exact: true}).click()
  await deliver(page, 0, "first.regent.eth", "next")
  await page.getByRole("button", {name: "More names"}).click()
  await page.evaluate(() => (window as any).requests[1].resolve({ok: false, status: 503}))
  await expect(page.getByRole("status")).toContainText("Try again")
  await page.getByRole("button", {name: "More names"}).click()
  await page.evaluate(() => (window as any).stop())
  await deliver(page, 2, "late.regent.eth")
  await expect(page.locator("li")).toHaveCount(0)
  await page.getByRole("button", {name: "Load names", exact: true}).click()
  expect(await page.evaluate(() => (window as any).requests.length)).toBe(3)
})

test("long historical evidence wraps on mobile and the disclosure works by keyboard", async ({page}) => {
  await page.setViewportSize({width: 390, height: 844})
  await page.getByRole("button", {name: "Load names", exact: true}).click()
  await deliver(page, 0, "long-name-".repeat(6) + ".regent.eth")
  await page.locator("summary").focus()
  await page.keyboard.press("Enter")
  await expect(page.locator("details")).toHaveAttribute("open", "")
  await expect(page.locator("dd").last()).toHaveText("0x" + "a".repeat(64))
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
})
