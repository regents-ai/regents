import {existsSync, readFileSync} from "node:fs"
import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// A visit can be told again from its lines alone (RegentsWeb.VisitLog). The
// walk's person opens Account and chooses an agent to pair, and the lines the
// server wrote for that visit (config/runtime.exs) say so in order: the request,
// the page, the pairing code the site made and the press that asked for it.
// Every line carries the same visit and the same one-way code for the person,
// holds only the visit fields, and holds nothing about the person or the code.

type Line = {
  time: string
  severity: string
  message: string
  metadata: {
    visit?: string
    actor?: string
    surface?: string
    request_id?: string
    event?: {name: string; where: string; outcome?: string; ms?: number; client?: string}
  }
}

// The walk's person (Regents.TestPrivyVerifier, bearer "valid").
const wallet = `0x${"1".repeat(40)}`

const fields = ["actor", "event", "request_id", "surface", "visit"]

function lines(visit: string): Line[] {
  const file = "tmp/walk-lines.jsonl"
  if (!existsSync(file)) return []
  return readFileSync(file, "utf8")
    .split("\n")
    .filter(text => text.includes(visit))
    .map(text => JSON.parse(text) as Line)
    .filter(line => line.metadata.visit === visit && line.metadata.event)
}

const step = (line: Line) => `${line.metadata.event!.name} ${line.metadata.event!.where}`

async function visitOf(page: Page): Promise<string> {
  return (await page.context().cookies()).find(cookie => cookie.name === "_visit")!.value
}

for (const width of [1280, 390]) {
  test(`choosing an agent to pair replays in order from the visit's lines at ${width}`, async ({page}) => {
    const errors: string[] = []
    page.on("pageerror", error => errors.push(error.message))
    await page.setViewportSize({width, height: 900})
    const auth = await installAuthenticatedPrivy(page, "valid")
    await auth.establishLocalSession()
    await page.goto("/account")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    await page.locator("#account-agents").getByRole("link", {name: "Pair New Agent"}).click()
    const radio = page.locator("#account-pairing").getByRole("radio", {name: "Dots", exact: true})
    await radio.locator("xpath=ancestor::label").click()
    const message = page.locator("#account-pairing-box pre")
    await expect(message).toContainText(/Pairing code:\s*\S{12,}/)
    const code = (await message.innerText()).match(/Pairing code:\s*(\S+)/)![1]

    const visit = await visitOf(page)
    await expect.poll(() => lines(visit).map(step)).toContain("press PairingBox:choose_agent")
    const told = lines(visit)
    const steps = told.map(step)

    expect(steps[0]).toBe("request /account")
    const order = [
      "request /account",
      "page /account",
      "action pairing_code.issue",
      "press PairingBox:choose_agent",
    ].map(wanted => steps.indexOf(wanted))
    expect(order.every(index => index >= 0)).toBe(true)
    expect([...order].sort((a, b) => a - b)).toEqual(order)
    expect(told.find(line => step(line) === "press PairingBox:choose_agent")!.metadata.event!.outcome).toBe("ok")

    const actors = [...new Set(told.map(line => line.metadata.actor))]
    expect(actors).toHaveLength(1)
    expect(actors[0]).toMatch(/^person:[0-9a-f]{16}$/)

    for (const line of told) {
      expect(Object.keys(line).sort()).toEqual(["message", "metadata", "severity", "time"])
      expect(Object.keys(line.metadata).every(key => fields.includes(key))).toBe(true)
      expect(
        Object.keys(line.metadata.event!).every(key => ["name", "where", "outcome", "ms", "client"].includes(key)),
      ).toBe(true)
      const text = JSON.stringify(line)
      for (const written of [code, wallet, "did:privy"]) expect(text).not.toContain(written)
    }
    expect(errors).toEqual([])
  })
}

// A page's own script reading the API joins its visit: the agent tools list on the
// home page reads every site's tools without cookies, and the read is the visit's.
// The home page has no handle_params of its own, and its opening is still a line.
test("the agent tools list's read belongs to the page's visit", async ({page}) => {
  await page.goto("/")
  await expect(page.locator(".phx-connected").first()).toBeAttached()
  await page.locator("#home-agent-tools-button").click()
  await expect(page.getByRole("dialog", {name: /^Agents see/})).toBeVisible()

  const visit = await visitOf(page)
  await expect.poll(() => lines(visit).map(step)).toContain("tool.call /api/v1/site-tools")
  expect(lines(visit).map(step)).toContain("page /")
  const read = lines(visit).find(line => step(line) === "tool.call /api/v1/site-tools")!
  expect(read.metadata.surface).toBe("page")
  expect(read.metadata.event!.client).toBe("none")
})
