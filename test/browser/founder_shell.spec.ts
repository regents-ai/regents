import {expect, test, type Page} from "@playwright/test"
import {
  installAuthenticatedPrivy,
  matchesAuthenticatedPrivyBridgeUrl,
} from "./support/authenticated_privy"

const shellRoutes = [
  "/app",
  "/formation",
  "/regents/regent",
  "/techtree",
  "/techtree/nodes/node-1",
  "/techtree/genebench-pro-reference-lab",
  "/autolaunch",
  "/autolaunch/auctions",
  "/autolaunch/auctions/auction-1",
  "/autolaunch/tokens",
  "/autolaunch/tokens/token-1",
  "/autolaunch/create",
  "/stake",
  "/redeem",
]

async function switchApp(page: Page, label: string) {
  await page.locator("#app-selector summary").click()
  await page.locator("#app-selector nav").getByRole("link", {name: label, exact: true}).click()
}

test("[U2] direct application loads seed the canonical RegentUI brand", async ({page}) => {
  for (const [route, brand] of [
    ["/formation", "platform"],
    ["/techtree", "techtree"],
    ["/autolaunch", "autolaunch"],
  ] as const) {
    await page.goto(route)
    await expect(page.locator("html")).toHaveAttribute("data-brand", brand)
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  }
})

test("all approved routes render within their page budget", async ({page, request}) => {
  const home = await request.get("/")
  expect(home.status()).toBe(200)
  expect((await home.body()).byteLength).toBeLessThanOrEqual(100 * 1024)

  for (const route of shellRoutes) {
    const response = await request.get(route)
    expect(response.status(), route).toBe(200)
    expect((await response.body()).byteLength, route).toBeLessThanOrEqual(100 * 1024)
  }

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toBeVisible()
})

test("the public homepage presents the four-product mat hero and marketing chapters", async ({page}) => {
  await page.goto("/")

  const home = page.locator("#public-home")
  await expect(home).toHaveAttribute("data-hero-enhanced", "true")
  await expect(page.locator(".rl-hero-art")).toHaveAttribute(
    "src",
    "/images/home/hero-bg-dark.svg",
  )
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(4)
  await expect(page.locator("#home-card-formation")).toHaveAttribute("href", "/formation")
  await expect(page.locator("#home-card-autolaunch")).toHaveAttribute("href", "/autolaunch")
  await expect(page.locator("#home-card-techtree")).toHaveAttribute("href", "/techtree")
  await expect(page.locator("#home-card-regent")).toHaveAttribute("href", "/app")

  const sectionTops = await page
    .locator("#formation, #autolaunch, #techtree, #regents-labs")
    .evaluateAll(elements => elements.map(element => element.getBoundingClientRect().top + scrollY))
  expect(sectionTops).toHaveLength(4)
  expect(sectionTops).toEqual([...sectionTops].sort((left, right) => left - right))
  expect(await page.evaluate(() => document.fonts.check('16px "GeistPixel Square"'))).toBe(true)
  await expect(page.locator("#app-shell")).toHaveCount(0)
  await expect(page.getByText("Public chatbox")).toHaveCount(0)
})

test("the primary homepage action keeps its contrast on hover", async ({page}) => {
  await page.goto("/")

  const action = page.getByRole("link", {name: "Form a Regent"}).first()
  const before = await action.evaluate(element => {
    const style = getComputedStyle(element)
    return {backgroundColor: style.backgroundColor, color: style.color}
  })

  await action.hover()

  await expect
    .poll(() =>
      action.evaluate(element => {
        const style = getComputedStyle(element)
        return {backgroundColor: style.backgroundColor, color: style.color}
      }),
    )
    .toEqual(before)
})

test("the four homepage destinations remain full-width and ordered on mobile", async ({page}) => {
  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/")

  const boxes = await page.locator("[data-home-hero-card]").evaluateAll(elements =>
    elements.map(element => {
      const box = element.getBoundingClientRect()
      return {left: box.left, right: box.right, top: box.top}
    }),
  )

  expect(boxes).toHaveLength(4)
  expect(boxes.map(box => box.top)).toEqual(
    [...boxes].map(box => box.top).sort((left, right) => left - right),
  )
  expect(boxes.every(box => box.left >= 0 && box.right <= 390)).toBe(true)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390)
})

test("anonymous Sign In stays separate from the app selector", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const appSelector = page.getByRole("navigation", {name: "Applications"})
  const accountControl = page.locator("#account-control")

  await expect(page.locator("#app-selector summary")).toContainText("Regents Labs")
  await expect(appSelector).toBeHidden()
  await page.locator("#app-selector summary").click()
  await expect(appSelector).toBeVisible()
  await expect(appSelector.getByRole("link")).toHaveCount(3)
  await expect(appSelector.getByRole("link", {name: "Regents Labs"})).toHaveCount(0)
  await expect(accountControl.getByRole("button", {name: "Sign In"})).toBeVisible()
  await expect(appSelector.getByRole("button", {name: "Sign In"})).toHaveCount(0)
  await expect(accountControl.getByRole("link", {name: "Nous Portal"})).toHaveCount(0)

  await page.evaluate(() => {
    const link = document.createElement("a")
    link.href = "/settings"
    link.textContent = "Anonymous Settings patch"
    link.dataset.phxLink = "patch"
    link.dataset.phxLinkState = "push"
    document.querySelector("#shell-header")?.append(link)
  })
  await page.getByRole("link", {name: "Anonymous Settings patch"}).click()
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole("heading", {name: "Settings"})).toHaveCount(0)
  await expect(page.getByRole("heading", {name: "Appearance"})).toHaveCount(0)

  await page.goto("/settings")
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole("heading", {name: "Settings"})).toHaveCount(0)
  await expect(page.getByRole("heading", {name: "Appearance"})).toHaveCount(0)
})

test("a signed-in account without a Regent shows its available account menu", async ({page}) => {
  const ashOrigin = "http://127.0.0.1:4002"
  const hashedBridge = "privy_bridge-0123456789abcdef0123456789abcdef.js"
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/privy_bridge.js?regent_retry=1`,
      ashOrigin,
    ),
  ).toBe(true)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/${hashedBridge}?vsn=d&regent_retry=2`,
      ashOrigin,
    ),
  ).toBe(true)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      "https://attacker.example/assets/js/privy_bridge.js?regent_retry=1",
      ashOrigin,
    ),
  ).toBe(false)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `https://attacker.example/assets/js/${hashedBridge}?vsn=d&regent_retry=2`,
      ashOrigin,
    ),
  ).toBe(false)
  expect(
    matchesAuthenticatedPrivyBridgeUrl(
      `${ashOrigin}/assets/js/privy_bridge.js?authenticated_privy_original=1`,
      ashOrigin,
    ),
  ).toBe(false)

  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("#shell-header [data-theme-choice]")).toHaveCount(0)
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})

  const account = page.locator("#account-menu")
  await expect(account.locator("img.account-avatar")).toHaveAttribute(
    "src",
    /^data:image\/svg\+xml;base64,/,
  )
  await expect
    .poll(() => account.locator("img.account-avatar").evaluate(image => image.naturalWidth))
    .toBeGreaterThan(0)
  await account.locator("summary").first().click()
  await expect(account.getByRole("link", {name: "Profile"})).toHaveCount(0)
  await expect(account.getByRole("link", {name: "Settings"})).toBeVisible()
  await expect(account.getByRole("button", {name: "Log Out"})).toBeVisible()

  await account.getByRole("link", {name: "Settings"}).click()
  await expect(page).toHaveURL(/\/settings$/)
  await expect(page.getByRole("heading", {name: "Settings", level: 1})).toBeVisible()
  await expect(page.getByRole("heading", {name: "Appearance", level: 2})).toBeVisible()
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 2, syncs: 1})

  const appearance = page.getByRole("group", {name: "Appearance"})
  await appearance.getByRole("button", {name: "Dark"}).click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  expect(await page.evaluate(() => localStorage.getItem("regent:theme"))).toBe("dark")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 3, syncs: 2})
})

test("Regents Labs overview shows public chain truth without inventing a profile", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const overview = page.locator("#regent-ops-overview")
  await expect(overview.getByRole("heading", {name: "Regents Labs"})).toBeVisible()
  await expect(overview).toContainText("100 REGENT")
  await expect(overview).toContainText("Sign in to see your wallet")
  await expect(overview.getByRole("link", {name: "Stake REGENT"})).toHaveAttribute(
    "href",
    "/stake",
  )
  await expect(overview.getByRole("link", {name: "Redeem Animata"})).toHaveAttribute(
    "href",
    "/redeem",
  )
  await expect(page.getByRole("link", {name: "Profile", exact: true})).toHaveCount(0)
})

test("an unknown public Regent profile is honest and keeps shell navigation available", async ({page}) => {
  await page.goto("/regents/not-here")

  await expect(page.locator("#public-regent-profile")).toBeVisible()
  await expect(page.getByRole("heading", {name: "Regent not found"})).toBeVisible()
  await expect(page.getByText("This public Regent profile does not exist.")).toBeVisible()
  await expect(page.locator("#app-selector summary")).toContainText("Regents Labs")
  await expect(page.getByRole("link", {name: "Return to Regents Labs"})).toHaveAttribute(
    "href",
    "/app",
  )
})

test("[U2][U6] navigation keeps brand, document, shell identity, and starts at the top", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  const shellInstance = await page.locator("#app-shell").getAttribute("data-shell-instance")
  await page.evaluate(() => {
    ;(window as Window & {founderShellDocument?: object}).founderShellDocument = {}
    const content = document.querySelector("#route-content")
    content?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await switchApp(page, "Techtree")
  await expect(page).toHaveURL(/\/techtree$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "techtree")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")

  expect(
    await page.evaluate(() => Boolean((window as Window & {founderShellDocument?: object}).founderShellDocument)),
  ).toBe(true)
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await switchApp(page, "Autolaunch")
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "autolaunch")
  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await page.goBack()
  await expect(page).toHaveURL(/\/techtree$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "techtree")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })
  await page.goForward()
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "autolaunch")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)
})

test("rapid app switches settle only the latest scene and remove motion copies", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await switchApp(page, "Techtree")
  await expect(page).toHaveURL(/\/techtree$/)
  await switchApp(page, "Autolaunch")

  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-motion-app", "autolaunch")
  await expect(page.getByRole("heading", {name: "Launch with public proof"})).toBeVisible()
  await expect(page.locator("[data-motion-copy]"), "outgoing copies are disposable").toHaveCount(0)
  await expect(page.locator("#route-content")).toHaveCSS("opacity", "1")
})

test("Map and List stay local without adding browser history", async ({page}) => {
  await page.goto("/techtree/genebench-pro-reference-lab")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const historyLength = await page.evaluate(() => history.length)
  await page.locator(".techtree-list-tab").click()

  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "list")
  await expect(page.locator("#route-content .techtree-list-panel")).toHaveCSS(
    "transform",
    "matrix(1, 0, 0, 1, 0, 0)",
  )
  expect(await page.evaluate(() => history.length)).toBe(historyLength)

  await page.locator(".techtree-map-tab").click()
  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "map")
  expect(await page.evaluate(() => history.length)).toBe(historyLength)
})

test("Techtree overview and node detail keep the initial web boundary honest", async ({page}) => {
  await page.goto("/techtree")
  await expect(page.getByRole("heading", {name: "Research with Techtree"})).toBeVisible()
  await expect(page.locator("#techtree-overview code")).toHaveText([
    "regents techtree start",
    "regents techtree node create",
  ])
  await expect(page.locator("#techtree-overview .techtree-roots a")).toHaveCount(5)

  await page.goto("/techtree/nodes/00000000-0000-0000-0000-000000000001")
  const node = page.locator("#techtree-node")
  await expect(node.getByRole("heading", {name: "Node not found"})).toBeVisible()
  await expect(node.getByRole("link", {name: "Publish", exact: true})).toHaveCount(0)
  await expect(node.getByRole("button", {name: "Publish", exact: true})).toHaveCount(0)
})

test("a Techtree notebook runs interactively in a credentialless cross-origin local-compute sandbox", async ({page}) => {
  test.setTimeout(120_000)
  await page.goto("/techtree/skill-training-lab")
  await page.getByRole("link", {name: "Browser notebook fixture"}).first().click()

  const iframe = page.locator("#local-notebook iframe")
  await expect(iframe).toHaveAttribute("sandbox", "allow-scripts allow-same-origin")
  await expect(iframe).toHaveAttribute("credentialless", "")

  const runUrl = await iframe.getAttribute("src")
  expect(runUrl).toMatch(
    /^http:\/\/127\.0\.0\.1:4003\/[0-9a-f]{64}\/index\.html$/,
  )
  const notebookResponse = await page.request.get(runUrl!)
  expect(notebookResponse.headers()["access-control-allow-origin"]).toBe("*")
  expect(notebookResponse.headers()["content-security-policy"]).toContain("default-src 'none'")

  const notebook = page.frameLocator("#local-notebook iframe")
  const notebookBody = notebook.locator("body")
  expect(await notebookBody.evaluate(() => document.cookie)).toBe("")
  await expect(notebookBody).toContainText("Local result: 6", {
    timeout: 90_000,
  })
  expect(
    await page.evaluate(() =>
      document.querySelector<HTMLIFrameElement>("#local-notebook iframe")?.contentDocument === null
    ),
  ).toBe(true)

  const slider = notebook.getByRole("slider")
  await expect(slider).toBeVisible({timeout: 90_000})
  await slider.press("ArrowRight")
  await slider.press("ArrowRight")
  await expect(notebookBody).toContainText("Local result: 10", {
    timeout: 30_000,
  })
})

test("node comments post once, update another reader live, preserve scroll, and delete cleanly", async ({
  browser,
  page,
}) => {
  const auth = await installAuthenticatedPrivy(page, "valid")
  await auth.establishLocalSession()

  const publicContext = await browser.newContext()
  const publicPage = await publicContext.newPage()
  const publicSession = await publicPage.request.get("/auth/session")
  const publicOrigin = new URL(publicSession.url()).origin
  expect(publicSession.status()).toBe(200)
  expect((await publicSession.json()).authenticated).toBe(false)
  const publicBridgeRequests: string[] = []
  publicPage.on("request", request => {
    if (matchesAuthenticatedPrivyBridgeUrl(request.url(), publicOrigin)) {
      publicBridgeRequests.push(request.url())
    }
  })
  await publicPage.goto("/techtree/skill-training-lab")
  expect(publicBridgeRequests).toEqual([])
  expect(
    await publicPage.evaluate(
      () => typeof (window as Window & {__authenticatedPrivyRecordSync?: unknown})
        .__authenticatedPrivyRecordSync,
    ),
  ).toBe("undefined")

  await page.goto("/techtree/skill-training-lab")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})
  await page.getByRole("link", {name: "Browser comment fixture"}).first().click()
  await expect(page.getByRole("heading", {name: "Browser comment fixture"})).toBeVisible()

  await publicPage.goto(page.url())
  await expect(publicPage.locator("#comment-ledger")).toContainText("Sign in to add a comment")
  expect(publicBridgeRequests).toEqual([])

  const publicScroller = publicPage.locator("#app-shell-scroller")
  await publicScroller.evaluate(element => element.scrollTo(0, element.scrollHeight))
  const scrollBefore = await publicScroller.evaluate(element => element.scrollTop)

  const uniqueCopy = `Browser proof ${Date.now()}`
  await page.getByLabel("Add a comment").fill(`**${uniqueCopy}**`)
  await page.getByRole("button", {name: "Post comment"}).click()

  const signedComment = page.locator("#comment-ledger article").filter({hasText: uniqueCopy})
  const publicComment = publicPage.locator("#comment-ledger article").filter({hasText: uniqueCopy})
  await expect(signedComment).toBeVisible()
  await expect(signedComment.locator(".comment-ledger__body strong")).toHaveText(uniqueCopy)
  await expect(publicComment).toBeVisible()
  expect(await publicScroller.evaluate(element => element.scrollTop)).toBe(scrollBefore)

  const reactionScrollBefore = await publicScroller.evaluate(element => element.scrollTop)
  await signedComment.getByRole("button", {name: "Useful 0"}).click()
  await expect(signedComment.getByRole("button", {name: "Useful 1"})).toHaveAttribute(
    "aria-pressed",
    "true",
  )
  await expect(publicComment.locator('[data-reaction-value="useful"]')).toHaveText("Useful 1")
  expect(await publicScroller.evaluate(element => element.scrollTop)).toBe(reactionScrollBefore)

  await signedComment.getByRole("button", {name: "Negative 0"}).click()
  await expect(signedComment.getByRole("button", {name: "Negative 1"})).toHaveAttribute(
    "aria-pressed",
    "true",
  )
  await expect(publicComment.locator('[data-reaction-value="useful"]')).toHaveText("Useful 0")

  await signedComment.getByRole("button", {name: "Negative 1"}).click()
  await expect(publicComment.locator('[data-reaction-value="negative"]')).toHaveText("Negative 0")

  page.once("dialog", dialog => void dialog.accept())
  await signedComment.getByRole("button", {name: "Delete"}).click()
  await expect(signedComment).toHaveCount(0)
  await expect(publicComment).toHaveCount(0)

  await publicContext.close()
})

test("Autolaunch overview, detail, and Create stay useful without fake market data", async ({page}) => {
  await page.goto("/autolaunch")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  const overview = page.locator("#autolaunch-overview")
  await expect(overview.getByRole("heading", {name: "Launch with public proof"})).toBeVisible()
  await expect(overview.locator(".autolaunch-market-section h2")).toHaveText([
    "Featured auctions",
    "Recently created",
    "Top tokens",
    "Recently graduated",
  ])
  await expect(overview).not.toContainText("$")

  await overview.getByRole("link", {name: "Create a launch"}).click()
  await expect(page).toHaveURL(/\/autolaunch\/create$/)
  await expect(page.locator("#autolaunch-verified-connections li strong")).toHaveText([
    "X",
    "GitHub",
    "Farcaster",
  ])
  await expect(
    page.locator("#autolaunch-verified-connections button", {
      hasText: "Sign in to connect",
    }),
  ).toHaveCount(3)
  await expect(page.locator("#autolaunch-create form")).toHaveCount(0)

  await page.goto("/autolaunch/auctions/auction-42")
  await expect(page.getByRole("heading", {name: "Auction not found"})).toBeVisible()
  await expect(page.locator("#autolaunch-auction-detail")).toContainText(
    "No public auction exists",
  )
})

test("a signed-in Regent owner saves a private launch draft without creating an auction", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-autolaunch-draft")
  await auth.establishLocalSession()

  await page.goto("/formation")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 1, sessionChecks: 1, syncs: 1})

  await page.goto("/autolaunch/create")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
  const uniqueTitle = `Browser launch draft ${Date.now()}`
  const draft = page.locator("#create-launch-draft")
  await draft.getByLabel("Launch title").fill(uniqueTitle)
  await draft.getByLabel("Token name").fill("Browser Draft")
  await draft.getByLabel("Token symbol").fill("BDRAFT")
  await draft.getByLabel("Public summary").fill("Private preparation only.")
  await draft.getByRole("button", {name: "Save private draft"}).click()

  await expect(page.getByText("Draft saved. No auction or wallet action has started.")).toBeVisible()
  await expect(page.locator("#launch-drafts article").filter({hasText: uniqueTitle})).toBeVisible()

  await page.goto("/autolaunch/auctions")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 3, sessionChecks: 3, syncs: 3})
  await expect(page.getByText(uniqueTitle)).toHaveCount(0)
})

test("tree names preserve presentation while explicit selectors force it", async ({page}) => {
  await page.goto("/techtree/genebench-pro-reference-lab")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await page.getByRole("link", {name: "GeneBench-Pro Reference Lab list"}).click()
  await page.getByRole("link", {name: "Question Forge Metaskills", exact: true}).click()

  await expect(page).toHaveURL(/\/techtree\/question-forge-metaskills$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "list")

  await page.getByRole("link", {name: "BixBench Capsule Lab map"}).click()
  await expect(page).toHaveURL(/\/techtree\/bixbench-capsule-lab$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-presentation", "map")
})

test("Formation keeps one in-shell heading and an exact inactive Nous handoff", async ({page}) => {
  const requests: string[] = []
  page.on("request", request => requests.push(request.url()))

  await page.goto("/formation")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.getByRole("heading")).toHaveCount(1)
  await expect(
    page.getByRole("heading", {level: 1, name: "Run your Regent in Nous Portal"}),
  ).toBeVisible()
  await expect(
    page.getByText("Create and manage your Regent’s cloud runtime in Nous Portal."),
  ).toBeVisible()

  const portal = page.getByRole("link", {name: "Open Nous Portal"})
  await expect(portal).toHaveAttribute("href", "https://portal.nousresearch.com/cloud")
  await expect(portal).toHaveAttribute("target", "_blank")
  await expect(portal).toHaveAttribute("rel", "noopener noreferrer")
  await expect(
    page.getByText("Nous Portal opens in a new tab. Your Regent session stays open here."),
  ).toBeVisible()

  await expect(page.locator("#formation-lifecycle form")).toHaveCount(0)
  await expect(page.locator("#formation-lifecycle button")).toHaveCount(0)
  await expect(
    page.locator("#formation-lifecycle [phx-click], #formation-lifecycle [phx-submit]"),
  ).toHaveCount(0)
  await expect(page.getByText("Form your Regent", {exact: true})).toHaveCount(0)
  await expect(page.getByText("Provision Sprite", {exact: true})).toHaveCount(0)
  expect(requests.some(url => url.startsWith("https://portal.nousresearch.com/"))).toBe(false)
})

test("Formation handoff keeps focus visible and fits narrow, landscape, and zoom viewports", async ({page}) => {
  for (const viewport of [
    {width: 320, height: 720},
    {width: 390, height: 844},
    {width: 844, height: 390},
    {width: 640, height: 900},
  ]) {
    await page.setViewportSize(viewport)
    await page.goto("/formation")
    await expect(page.locator("#formation-nous-portal-link")).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      viewport.width,
    )

    await page.locator("#formation-nous-portal-link").evaluate(element => {
      ;(element as HTMLElement).focus({focusVisible: true})
    })
    await expect(page.locator("#formation-nous-portal-link:focus-visible")).toBeVisible()
    await expect(page.locator("#formation-nous-portal-link")).toHaveCSS("outline-style", "solid")
  }
})

test("theme and reduced-motion preferences apply immediately", async ({browser}) => {
  const context = await browser.newContext({reducedMotion: "reduce"})
  const page = await context.newPage()
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  await expect(page.locator("html")).toHaveAttribute("data-reduced-motion", "true")
  await page.locator("#theme-control summary").click()
  await page.locator("#theme-control").getByRole("button", {name: "Dark"}).click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await context.close()
})

for (const width of [320, 390]) {
  test(`${width}px drawer contains focus and cleans up every close path`, async ({page}) => {
    await page.setViewportSize({width, height: 720})
    await page.goto("/techtree")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    const menu = page.getByRole("button", {name: "Menu"})
    const sidebar = page.getByRole("navigation", {name: "Context navigation"})
    const scrim = page.locator("[data-shell-menu-scrim]")
    const scroller = page.locator("#app-shell-scroller")

    await menu.click()
    await expect(menu).toHaveAttribute("aria-expanded", "true")
    await expect(sidebar).toBeVisible()
    await expect(scrim).toBeVisible()
    await expect(scroller).toHaveAttribute("inert", "")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)

    await page.keyboard.press("Shift+Tab")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)
    await page.keyboard.press("Tab")
    expect(await sidebar.evaluate(element => element.contains(document.activeElement))).toBe(true)

    await page.keyboard.press("Escape")
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()
    await expect(scrim).toBeHidden()
    await expect(scroller).not.toHaveAttribute("inert", "")

    await menu.click()
    await scrim.click({position: {x: width - 2, y: 10}})
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()

    await menu.click()
    await sidebar.getByRole("button", {name: "Close navigation"}).click()
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(menu).toBeFocused()

    await menu.click()
    const destination = sidebar.locator('a[href]:not([href="/techtree"])').first()
    await destination.click()
    await expect(menu).toHaveAttribute("aria-expanded", "false")
    await expect(scrim).toBeHidden()
    await expect(scroller).not.toHaveAttribute("inert", "")

    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width)
    await expect(page.getByRole("banner")).toHaveCount(1)
    await expect(page.getByRole("main")).toHaveCount(1)
  })
}

test("tablet, desktop, and effective 200 percent zoom have no horizontal overflow", async ({page}) => {
  for (const viewport of [
    {width: 768, height: 1024},
    {width: 1280, height: 800},
    {width: 640, height: 900},
  ]) {
    await page.setViewportSize(viewport)
    await page.goto("/techtree")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      viewport.width,
    )
  }
})
