import type {Page, Request} from "@playwright/test"
import {expect, test} from "./support/offline"

// The page's signed tools as an agent's browser host sees them. Chromium here has
// no WebMCP, so a stand-in document.modelContext holds what the page registers; a
// stand-in window.regentsSign plays the agent's signer (regents browser in use).
// A signed tool takes only its input: the host signs the exact request the page
// built, and the page sends those bytes, or nothing at all. The walk's server
// cannot check a signature, so the one signed send is answered in the browser.
const withPageTools = `
  const held = new Map()
  Object.defineProperty(document, "modelContext", {value: {
    registerTool: async (tool, {signal}) => {
      held.set(tool.name, tool)
      signal.addEventListener("abort", () => held.delete(tool.name))
    },
  }})
  window.pageTools = held
`

type Signer = "none" | "signs" | "refuses"

const proof = {
  "x-siwa-signature": "sig1=:c2ln:",
  "x-siwa-signature-input": "sig1=(\"@method\");created=1",
  "x-siwa-receipt": "receipt",
  "x-key-id": "0x2222222222222222222222222222222222222222",
  "x-timestamp": "1",
  "x-agent-wallet-address": "0x2222222222222222222222222222222222222222",
  "x-agent-chain-id": "8453",
  "content-digest": "sha-256=:ZGlnZXN0:",
}

const history = "/api/agent/v1/credits/history"
const answer = {entries: [], pagination: {has_more: false, next_cursor: null}}

async function open(page: Page, signer: Signer, width: number) {
  await page.setViewportSize({width, height: 900})
  await page.addInitScript(withPageTools)
  await page.addInitScript(([signer, proof]) => {
    const asked: unknown[] = []
    ;(window as unknown as {signerAsked: unknown[]}).signerAsked = asked
    if (signer === "signs") {
      Object.assign(window, {regentsSign: async (request: unknown) => (asked.push(request), {headers: proof})})
    } else if (signer === "refuses") {
      Object.assign(window, {regentsSign: async (request: unknown) => (asked.push(request), {
        error: {code: "call_mismatch", message: "This is not the call your agent made.", hint: "Call the tool again."},
      })})
    }
  }, [signer, proof] as const)
  await page.route(`**${history}`, route => route.fulfill({json: answer}))
  await page.goto("/")
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.webmcpStatus)).toBe("ready")
}

const call = (page: Page, name: string, input: unknown) =>
  page.evaluate(([name, input]) => {
    const tools = (window as unknown as {pageTools: Map<string, {execute: Function}>}).pageTools
    return tools.get(name)!.execute(input, {})
  }, [name, input] as const)

const toApi = (page: Page) => {
  const sent: Request[] = []
  page.on("request", request => { if (new URL(request.url()).pathname.startsWith("/api/")) sent.push(request) })
  return sent
}

const asked = (page: Page) =>
  page.evaluate(() => (window as unknown as {signerAsked: Array<Record<string, string>>}).signerAsked)

for (const width of [1280, 390]) {
  test(`a signed tool lists only its own input at ${width}`, async ({page}) => {
    await open(page, "none", width)
    const fields = await page.evaluate(() => {
      const tools = (window as unknown as {pageTools: Map<string, {inputSchema: {properties: object}}>}).pageTools
      return Object.keys(tools.get("regents_credits_history")!.inputSchema.properties)
    })
    expect(fields).toEqual(["after"])
  })

  test(`with no agent signer a signed tool sends nothing and says how to get one at ${width}`, async ({page}) => {
    await open(page, "none", width)
    const sent = toApi(page)
    const reply = await call(page, "regents_credits_history", {})
    expect(reply).toMatchObject({ok: false, error: {code: "agent_auth_required"}})
    expect((reply as {error: {hint: string}}).error.hint).toContain("regents browser --site regents")
    expect(sent).toEqual([])
  })

  test(`a signer's refusal is the tool's answer, and nothing is sent at ${width}`, async ({page}) => {
    await open(page, "refuses", width)
    const sent = toApi(page)
    const reply = await call(page, "regents_credits_history", {})
    expect(reply).toEqual({ok: false, error: {code: "call_mismatch", message: "This is not the call your agent made.", hint: "Call the tool again."}})
    expect(sent).toEqual([])
  })

  test(`the page sends exactly the request the signer signed, with its proof and no cookie, at ${width}`, async ({page, baseURL}) => {
    await open(page, "signs", width)
    const sent = toApi(page)
    const reply = await call(page, "regents_credits_history", {after: "next-page"})
    expect(reply).toEqual({ok: true, status: 200, body: answer})

    const [signed, ...more] = await asked(page)
    expect(more).toEqual([])
    expect(signed).toMatchObject({operation: "regents_credits_history", audience: "regents", origin: new URL(baseURL!).origin, method: "POST", path: history})
    expect(JSON.parse(signed.body)).toEqual({after: "next-page"})

    expect(sent).toHaveLength(1)
    const [request] = sent
    expect(request.method()).toBe("POST")
    expect(new URL(request.url()).pathname).toBe(history)
    expect(request.postData()).toBe(signed.body)
    const headers = await request.allHeaders()
    for (const [name, value] of Object.entries(proof)) expect(headers[name]).toBe(value)
    expect(headers.cookie).toBeUndefined()

    // An input the tool does not take is refused before the signer is asked.
    const refused = await call(page, "regents_credits_history", {after: "next-page", colour: "blue"})
    expect(refused).toMatchObject({ok: false, error: {code: "invalid_request"}})
    expect(await asked(page)).toHaveLength(1)
    expect(sent).toHaveLength(1)
  })
}
