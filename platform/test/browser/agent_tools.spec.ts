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
