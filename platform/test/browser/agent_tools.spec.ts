import {existsSync, readFileSync} from "node:fs"
import {expect, test, type Page} from "./support/offline"

// The test server answers every site's tools from the fixed lists in
// Regents.TestSiteTools: three tools for each site, named after its address.
const sites = ["regents.sh", "patchbay.help", "techtree.sh", "autolaunch.sh", "keyfleet.ai"]

// Sean, 19 Oct: the "Agents see" window copies every Regent site's tools at
// once, each site its own section, then how an agent signs in.
for (const width of [1280, 390]) {
  test(`the tools window copies every site's tools at ${width}`, async ({page, context}) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"])
    await page.setViewportSize({width, height: 900})
    // The page's live connection waits until the window is open, so it is
    // opened before the page connects, as an early press would, and must stay
    // open through the connection.
    let opened = () => {}
    const open = new Promise<void>(resolve => (opened = resolve))
    await page.routeWebSocket(/\/live\/websocket/, async socket => {
      await open
      socket.connectToServer()
    })
    await page.goto("/")

    await page.locator("#home-agent-tools-button").click()
    const dialog = page.getByRole("dialog", {name: /^Agents see \d+ WebMCP Tools$/})
    await expect(dialog).toBeVisible()
    opened()
    await page.locator(".phx-connected").first().waitFor()
    await expect(dialog).toBeVisible()
    const copyAll = dialog.locator("#home-agent-tools-copy-all")
    await expect(copyAll).toHaveAccessibleName("Copy all Regents WebMCP tools")
    await expect(copyAll).toBeEnabled()
    await expect(dialog.locator("[data-agent-tools-note]")).toHaveText("15 tools from 5 sites")

    await copyAll.click()
    // The button answers "Copied" in place of its words.
    await expect(copyAll).toHaveAccessibleName("Copied")
    const text = await page.evaluate(() => navigator.clipboard.readText())
    expect(text.startsWith("# WebMCP tools on every Regent site\n\n## regents.sh\n\n3 WebMCP tools\n")).toBe(true)
    const headings = [...text.matchAll(/^## (.+)$/gm)].map(match => match[1])
    expect(headings).toEqual([...sites, "siwa-server"])
    for (const site of sites) expect(text).toContain(`\`post_${site.replace(".", "_")}\``)
    expect(text).toContain("### Get the client")

    // The copy of the window's own list stays beside it.
    await expect(dialog.getByRole("button", {name: "Copy as Markdown"})).toBeVisible()
  })
}

type Registered = {name: string; execute(input: unknown): Promise<unknown>}

// Every page offers the list tools: one for each site and the complete list.
async function pageTools(page: Page, path: string): Promise<string[]> {
  await page.addInitScript(() => {
    const tools: Registered[] = []
    Object.assign(window, {registeredTools: tools})
    Object.defineProperty(document, "modelContext", {
      value: {registerTool: (tool: Registered) => void tools.push(tool)},
    })
  })
  await page.goto(path)
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.webmcpStatus)).toBe("ready")
  return page.evaluate(() => (window as unknown as {registeredTools: Registered[]}).registeredTools.map(tool => tool.name))
}

const call = (page: Page, name: string) =>
  page.evaluate(
    name => (window as unknown as {registeredTools: Registered[]}).registeredTools.find(tool => tool.name === name)!.execute({}),
    name,
  )

test("every page offers a list of each site's tools and the complete list", async ({page}) => {
  const names = await pageTools(page, "/docs")
  expect(names).toEqual(
    expect.arrayContaining([
      "list_regents_webmcp_tools",
      "list_patchbay_webmcp_tools",
      "list_techtree_webmcp_tools",
      "list_autolaunch_webmcp_tools",
      "list_keyfleet_webmcp_tools",
      "list_all_webmcp_tools",
      "get_siwa_connection_help",
    ]),
  )

  // A site's list holds every tool it publishes, on whichever page it offers them.
  const patchbay = (await call(page, "list_patchbay_webmcp_tools")) as {
    ok: boolean
    body: {site: string; tools: {name: string}[]}
  }
  expect(patchbay.ok).toBe(true)
  expect(patchbay.body.site).toBe("patchbay.help")
  expect(patchbay.body.tools.map(tool => tool.name)).toEqual([
    "browse_patchbay_help",
    "search_patchbay_help",
    "post_patchbay_help",
  ])

  const all = (await call(page, "list_all_webmcp_tools")) as {
    ok: boolean
    body: {sites: {site: string; tools: unknown[]}[]; unreachable: string[]; connection: {steps: unknown[]}}
  }
  expect(all.ok).toBe(true)
  expect(all.body.sites.map(site => site.site)).toEqual(sites)
  expect(all.body.sites.every(site => site.tools.length === 3)).toBe(true)
  expect(all.body.unreachable).toEqual([])
  expect(all.body.connection.steps).toHaveLength(4)
})

// R4: an agent pairs from the page with the bytes it signed, as `agents pair` sends
// them. The code goes only in the signed body: never in the address, the answer or
// the server's lines.
test("an agent pairs from the page with exactly the request it signed", async ({page}) => {
  await pageTools(page, "/docs")
  const run = (name: string, input: unknown) =>
    page.evaluate(
      ([name, input]) =>
        (window as unknown as {registeredTools: Registered[]}).registeredTools.find(tool => tool.name === name)!.execute(input),
      [name, input] as const,
    )
  const pairing = {code: `code-${crypto.randomUUID()}`, name: "Ada", harness: "claude_code"}

  // A harness the site does not offer is refused before anything is prepared.
  expect(await run("prepare_agent_request", {operation: "regents_agent_pair", input: {...pairing, harness: "robot"}}))
    .toMatchObject({ok: false, error: {code: "invalid_input"}})

  const prepared = (await run("prepare_agent_request", {operation: "regents_agent_pair", input: pairing})) as {
    ok: boolean
    request: {method: string; path: string; body: string}
  }
  expect(prepared.request).toMatchObject({operation: "regents_agent_pair", method: "POST", path: "/api/agents/v1/pair"})
  expect(JSON.parse(prepared.request.body)).toEqual(pairing)

  const sent = page.waitForRequest(request => new URL(request.url()).pathname === "/api/agents/v1/pair")
  const proof = {
    "x-siwa-signature": "sig=:AA==:",
    "x-siwa-signature-input": "sig=()",
    "x-siwa-receipt": "receipt",
    "x-key-id": "key",
    "x-timestamp": "1",
    "x-agent-wallet-address": `0x${"2".repeat(40)}`,
    "x-agent-chain-id": "8453",
    "content-digest": "sha-256=:AA==:",
  }
  const answer = await run("regents_agent_pair", {input: pairing, request: prepared.request, proof})
  const request = await sent
  expect(new URL(request.url()).search).toBe("")
  expect(request.postData()).toBe(prepared.request.body)
  expect(JSON.stringify(answer)).not.toContain(pairing.code)

  const requestId = (await request.response())!.headers()["x-request-id"]
  const file = "tmp/walk-lines.jsonl"
  const logged = () => (existsSync(file) ? readFileSync(file, "utf8") : "")
  await expect.poll(() => logged().includes(requestId)).toBe(true)
  expect(logged()).not.toContain(pairing.code)
})
