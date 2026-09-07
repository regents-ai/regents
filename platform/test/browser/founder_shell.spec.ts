import {expect, test, type Page} from "@playwright/test"
import {
  installAuthenticatedPrivy,
  matchesAuthenticatedPrivyBridgeUrl,
} from "./support/authenticated_privy"

const shellRoutes = [
  "/app",
  "/formation",
  "/regents/regent",
  "/autolaunch",
  "/autolaunch/auctions",
  "/autolaunch/auctions/auction-1",
  "/autolaunch/tokens",
  "/autolaunch/tokens/token-1",
  "/autolaunch/create",
  "/stake",
  "/redeem",
]

// The shell holds one live session across every application, so a link to another
// application patches the page it is already on. Content links do this in the product;
// the test raises one so the patch can be exercised from any route.
async function patchTo(page: Page, path: string) {
  await page.evaluate(destination => {
    document.querySelector("#patch-probe")?.remove()
    const link = document.createElement("a")
    link.id = "patch-probe"
    link.href = destination
    link.textContent = destination
    link.dataset.phxLink = "patch"
    link.dataset.phxLinkState = "push"
    document.querySelector("#route-content")?.append(link)
  }, path)

  await page.locator("#patch-probe").click()
}

// The mat guide is the slot's token, painted through `--shell-background-guide`:
// `--color-accent` on Regent routes, `--product-formation` on Formation, and
// `--brand-accent` on Autolaunch. Those tokens are read as computed colours so
// the assertion follows the stylesheet rather than a frozen rgb() string.
const routeGuideTokens = {
  "/stake": "--color-accent",
  "/formation": "--product-formation",
  "/autolaunch": "--brand-accent",
} as const

function tokenColor(page: Page, token: string) {
  return page.evaluate(name => {
    const probe = document.createElement("span")
    probe.style.backgroundColor = `var(${name})`
    document.documentElement.append(probe)
    const color = getComputedStyle(probe).backgroundColor
    probe.remove()
    return color
  }, token)
}

// The guide is read where it is painted, so it proves the whole chain from the
// shared token through `--shell-background-guide` onto the mat mask.
function readFamily(page: Page) {
  return page.evaluate(() => {
    const shell = document.querySelector("#app-shell")
    const asset = document.querySelector(".shell-background__asset")
    return {
      ground: shell && getComputedStyle(shell).backgroundColor,
      text: shell && getComputedStyle(shell).color,
      guide: asset && getComputedStyle(asset).backgroundColor,
    }
  })
}

async function chooseTheme(page: Page, choice: "light" | "dark") {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  if ((await page.locator("html").getAttribute("data-theme")) !== choice) {
    await page.locator("#theme-control [data-theme-toggle]").click()
  }
  await expect(page.locator("html")).toHaveAttribute("data-theme", choice)
}

test("[U2] the shell keeps one ground per theme while the mat guide follows each application", async ({page}) => {
  const palette: Record<string, {ground: string | null; text: string | null}> = {}

  for (const choice of ["light", "dark"] as const) {
    await chooseTheme(page, choice)

    for (const [route, token] of Object.entries(routeGuideTokens)) {
      await page.goto(route)
      await expect(page.locator("html")).toHaveAttribute("data-theme", choice)
      const guide = await tokenColor(page, token)
      await expect.poll(() => readFamily(page).then(read => read.guide), `${route} ${choice}`)
        .toBe(guide)

      const {ground, text} = await readFamily(page)
      palette[choice] ??= {ground, text}
      expect({ground, text}, `${route} ${choice}`).toEqual(palette[choice])
    }

    // Switching inside the persistent shell must land the same guide a direct
    // load does, on the same ground.
    await page.goto("/app")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

    await patchTo(page, "/formation")
    await expect(page).toHaveURL(/\/formation$/)
    await expect.poll(() => readFamily(page), `switched Formation ${choice}`).toEqual({
      ...palette[choice],
      guide: await tokenColor(page, routeGuideTokens["/formation"]),
    })

    await patchTo(page, "/autolaunch")
    await expect(page).toHaveURL(/\/autolaunch$/)
    await expect.poll(() => readFamily(page), `switched Autolaunch ${choice}`).toEqual({
      ...palette[choice],
      guide: await tokenColor(page, routeGuideTokens["/autolaunch"]),
    })
  }

  // Two themes, two grounds: the switch is not decorative.
  expect(palette.light).not.toEqual(palette.dark)
})

test("[U2] direct application loads seed the canonical RegentUI brand", async ({
  page,
  request,
}) => {
  for (const [route, brand] of [
    ["/formation", "platform"],
    ["/autolaunch", "autolaunch"],
  ] as const) {
    const served = await (await request.get(route)).text()
    expect(served).toContain(`data-brand="${brand}"`)
    expect(served).toContain('data-theme="dark"')

    await page.goto(route)
    await expect(page.locator("html")).toHaveAttribute("data-brand", brand)
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  }
})

test("product headings keep the interface face RegentUI would otherwise reface", async ({page}) => {
  await page.goto("/formation")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  expect(
    await page
      .locator(".formation-heading h1")
      .evaluate(element => getComputedStyle(element).fontFamily),
  ).toContain("Geist UI Sans")
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

test("the public homepage presents the product hero and marketing chapters", async ({page}) => {
  await page.goto("/")

  const home = page.locator("#public-home")
  await expect(home).toHaveAttribute("data-hero-enhanced", "true")
  await expect(page.locator(".rl-hero-art")).toHaveAttribute(
    "src",
    "/images/home/hero-bg-dark.svg",
  )
  await expect(page.locator("#home-title")).toHaveText("Regents Labs")
  // The cards name the three products; the chapters below them are a separate story.
  await expect(page.locator("[data-home-hero-card]")).toHaveCount(3)
  expect(
    await page
      .locator("[data-home-hero-card]")
      .evaluateAll(elements => elements.map(element => element.dataset.homeHeroCard)),
  ).toEqual(["autolaunch", "techtree", "patchbay"])
  await expect(page.locator(".rl-hero-stakers")).toBeVisible()

  const sectionTops = await page
    .locator("#techtree, #autolaunch, #patchbay")
    .evaluateAll(elements => elements.map(element => element.getBoundingClientRect().top + scrollY))
  expect(sectionTops).toHaveLength(3)
  expect(sectionTops).toEqual([...sectionTops].sort((left, right) => left - right))
  expect(await page.evaluate(() => document.fonts.check('16px "GeistPixel Square"'))).toBe(true)
  await expect(page.locator("#app-shell")).toHaveCount(0)
  await expect(page.getByText("Public chatbox")).toHaveCount(0)
})

// Headless Chromium has no GPU, which is the interesting case: the hero decoration
// must stay invisible and inert while the server's art, copy, and action carry the
// page on their own. Nothing here pretends a GPU is present.
test("the hero fallback and simulated-ready crown never block the action", async ({page}) => {
  for (const viewport of [
    {width: 1280, height: 800},
    {width: 390, height: 844},
  ]) {
    await page.setViewportSize(viewport)
    await page.goto("/")

    const prism = page.locator("#home-prism")
    await expect(prism).toHaveAttribute("aria-hidden", "true")
    await expect(prism).not.toHaveAttribute("data-prism-ready", "true")
    await expect(prism).toHaveCSS("opacity", "0")
    await expect(prism).toHaveCSS("transform", "none")
    await expect(prism).toHaveCSS("transition-property", "opacity")
    await expect(prism).toHaveCSS("pointer-events", "none")
    const canvas = page.locator("#home-prism canvas")
    await expect(canvas).toHaveCount(1)
    await expect(canvas).toHaveCSS("pointer-events", "none")
    await expect(page.locator(".rl-hero-art")).toBeVisible()
    await expect(page.locator("#home-title")).toBeVisible()

    // The full-hero canvas lies over the hero's own controls, so they must still
    // be reachable: a trial click runs every actionability check and presses nothing.
    const staking = page.locator(".rl-hero-stakers").getByRole("link", {name: "Stake REGENT"})
    await staking.click({trial: true})
    await page.locator("#home-card-techtree").getByRole("link", {name: "Open techtree"}).click({
      trial: true,
    })
    await expect(page.locator("#home-products")).toBeVisible()

    // Simulate the state reached only after the real GPU's first frame settles.
    // This is deliberately a presentation-state check, not a fake WebGPU adapter.
    // Reduced motion keeps the renderer dormant so its asynchronous adapter probe
    // cannot race this deliberately synthetic presentation state.
    await page.emulateMedia({reducedMotion: "reduce"})
    await page.goto("/")
    await prism.evaluate(element => (element as HTMLElement).dataset.prismReady = "true")
    await expect(prism).toHaveAttribute("data-prism-ready", "true")
    await expect(prism).toHaveCSS("opacity", "1")
    await expect(prism).toHaveCSS("transform", "none")
    await expect(prism).toHaveCSS("transition-property", "opacity")
    await expect(prism).toHaveCSS("pointer-events", "none")
    await expect(canvas).toHaveCSS("pointer-events", "none")
    await staking.click({trial: true})
    await expect(page.locator("#home-products")).toBeVisible()
    await prism.evaluate(element => delete (element as HTMLElement).dataset.prismReady)
    await expect(prism).toHaveCSS("opacity", "0")
    await expect(prism).toHaveCSS("transform", "none")
    await page.emulateMedia({reducedMotion: "no-preference"})
  }
})

test("the primary homepage action keeps its contrast on hover", async ({page}) => {
  await page.goto("/")

  const action = page.getByRole("link", {name: "Explore the system"})
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

test("the three homepage product cards remain full-width and ordered on mobile", async ({page}) => {
  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/")

  const boxes = await page.locator("[data-home-hero-card]").evaluateAll(elements =>
    elements.map(element => {
      const box = element.getBoundingClientRect()
      return {left: box.left, right: box.right, top: box.top}
    }),
  )

  expect(boxes).toHaveLength(3)
  expect(boxes.map(box => box.top)).toEqual(
    [...boxes].map(box => box.top).sort((left, right) => left - right),
  )
  expect(boxes.every(box => box.left >= 0 && box.right <= 390)).toBe(true)
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390)
})

test("anonymous Sign In stays separate from the brand link", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const brand = page.locator("#shell-brand")
  const accountControl = page.locator("#account-control")

  await expect(brand).toContainText("Regents Labs")
  await expect(brand).toHaveAttribute("href", "/")
  await expect(brand.getByRole("button")).toHaveCount(0)
  await expect(accountControl.getByRole("button", {name: "Sign In"})).toBeVisible()
  await expect(accountControl.getByRole("link", {name: "Nous Portal"})).toHaveCount(0)
  await expect(accountControl.getByRole("link", {name: "Settings"})).toHaveCount(0)
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
  await expect(page.locator("#theme-control [data-theme-toggle]")).toBeVisible()
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
  await expect(account.getByRole("link", {name: "Settings"})).toHaveCount(0)
  await expect(account.getByRole("button", {name: "Disconnect"})).toBeVisible()

  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await page.locator("#theme-control [data-theme-toggle]").click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  expect(await page.evaluate(() => document.cookie)).toContain("regent_theme=light")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 2, sessionChecks: 2, syncs: 2})
})

test("the Overview maps the four products, keeps account details secondary, and reaches Formation", async ({page}) => {
  await page.goto("/app")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const overview = page.locator("#regent-ops-overview")
  await expect(overview.getByRole("heading", {level: 1})).toBeVisible()

  const products = overview.getByRole("list", {name: "Products"})
  for (const name of ["Regents", "Autolaunch", "Techtree", "Patchbay"]) {
    await expect(products.getByRole("heading", {level: 2, name})).toBeVisible()
  }
  await expect(products.getByRole("link", {name: "Open Autolaunch"})).toHaveAttribute(
    "href",
    "https://autolaunch.sh",
  )
  await expect(page.locator("#shell-brand")).toContainText("Regents Labs")

  // Account details sit behind a closed disclosure for a visitor; opening it
  // shows the shared reading and the sign-in prompt, never an invented wallet.
  const account = page.locator("#regent-ops-account")
  await expect(account).not.toHaveAttribute("open", "")
  await account.locator("summary").click()
  await expect(account).toHaveAttribute("open", "")
  await expect(overview.getByLabel("Account summary")).toBeVisible()
  await expect(overview).toContainText("100 REGENT")
  await expect(overview).toContainText(
    "Sign in to see any wallet verified on your account and the balances available to it.",
  )

  const actions = overview.getByRole("navigation", {name: "Account actions"})
  await expect(actions.getByRole("link", {name: "Stake REGENT"})).toHaveAttribute("href", "/stake")
  await expect(actions.getByRole("link", {name: "Redeem Animata"})).toHaveAttribute(
    "href",
    "/redeem",
  )
  await expect(actions.getByRole("link", {name: "Run your Regent"})).toHaveAttribute(
    "href",
    "/formation",
  )
  await expect(overview.locator('a[href*="/hermes"]')).toHaveCount(0)
  await expect(page.getByRole("link", {name: "Profile", exact: true})).toHaveCount(0)

  await actions.getByRole("link", {name: "Run your Regent"}).click()
  await expect(page).toHaveURL(/\/formation$/)
  await expect(
    page.getByRole("heading", {level: 1, name: "Regent runs best on Hermes"}),
  ).toBeVisible()
})

test("an unknown public Regent profile is honest and keeps shell navigation available", async ({page}) => {
  await page.goto("/regents/not-here")

  await expect(page.locator("#public-regent-profile")).toBeVisible()
  await expect(page.getByRole("heading", {name: "Regent not found"})).toBeVisible()
  await expect(page.getByText("This public Regent profile does not exist.")).toBeVisible()
  await expect(page.locator("#shell-brand")).toContainText("Regents Labs")
  await expect(page.getByRole("link", {name: "Return to Overview"})).toHaveAttribute("href", "/app")
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

  await patchTo(page, "/formation")
  await expect(page).toHaveURL(/\/formation$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-shell-instance", shellInstance ?? "")

  expect(
    await page.evaluate(() => Boolean((window as Window & {founderShellDocument?: object}).founderShellDocument)),
  ).toBe(true)
  expect(await page.locator("#app-shell-scroller").evaluate(element => element.scrollTop)).toBe(0)

  await patchTo(page, "/autolaunch")
  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "autolaunch")
  await page.evaluate(() => {
    document
      .querySelector("#route-content")
      ?.insertAdjacentHTML("beforeend", '<div style="height:2000px"></div>')
    document.querySelector("#app-shell-scroller")?.scrollTo(0, 1000)
  })

  await page.goBack()
  await expect(page).toHaveURL(/\/formation$/)
  await expect(page.locator("html")).toHaveAttribute("data-brand", "platform")
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

  await patchTo(page, "/formation")
  await expect(page).toHaveURL(/\/formation$/)
  await patchTo(page, "/autolaunch")

  await expect(page).toHaveURL(/\/autolaunch$/)
  await expect(page.locator("#app-shell")).toHaveAttribute("data-motion-app", "autolaunch")
  await expect(page.getByRole("heading", {name: "Launch with public proof"})).toBeVisible()
  await expect(page.locator("[data-motion-copy]"), "outgoing copies are disposable").toHaveCount(0)
  await expect(page.locator("#route-content")).toHaveCSS("opacity", "1")
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
  await expect(page.locator("#autolaunch-create")).toContainText(
    "Sign in to prepare your launch.",
  )
  await expect(page.locator("#autolaunch-create form")).toHaveCount(0)

  await page.goto("/autolaunch/auctions/auction-42")
  await expect(page.getByRole("heading", {name: "Auction not found"})).toBeVisible()
  await expect(page.locator("#autolaunch-auction-detail")).toContainText(
    "No public auction exists",
  )
})

const draftTreasury = "0xAbCdeF0000000000000000000000000000000001"

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

  const uniqueName = `Browser launch draft ${Date.now()}`
  const draft = page.locator("#create-launch-draft")
  await draft.getByLabel("Name", {exact: true}).fill(uniqueName)
  await draft.getByLabel("Symbol", {exact: true}).fill("bdraft")
  await draft.getByLabel("Description", {exact: true}).fill("Private preparation only.")
  await draft.getByLabel("Website", {exact: true}).fill("https://example.test/browser-draft")
  await draft.getByLabel("Image", {exact: true}).fill("https://example.test/browser-draft.png")
  await draft.getByLabel("Immutable treasury recipient", {exact: true}).fill(draftTreasury)
  await draft.getByLabel("Required raise in REGENT", {exact: true}).fill("1000.5")
  await draft.getByRole("button", {name: "Save draft"}).click()

  await expect(page.getByText("Draft saved.")).toBeVisible()
  const card = page.locator("#launch-drafts article").filter({hasText: uniqueName})
  await expect(card).toBeVisible()
  await expect(card.locator(".autolaunch-draft-review")).toContainText(draftTreasury)
  await expect(card.locator(".autolaunch-draft-review")).toContainText("1000.5")

  await page.goto("/autolaunch/auctions")
  await auth.expectAuthenticatedSession()
  await auth.expectCounts({documents: 3, sessionChecks: 3, syncs: 3})
  await expect(page.getByText(uniqueName)).toHaveCount(0)
})

test("Create fits a 390px viewport and wraps long draft values instead of cutting them", async ({page}) => {
  const auth = await installAuthenticatedPrivy(page, "valid-autolaunch-draft")
  await auth.establishLocalSession()

  await page.setViewportSize({width: 390, height: 844})
  await page.goto("/formation")
  await auth.expectAuthenticatedSession()

  await page.goto("/autolaunch/create")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")

  const uniqueName = `Narrow viewport draft ${Date.now()}`
  const draft = page.locator("#create-launch-draft")
  await draft.getByLabel("Name", {exact: true}).fill(uniqueName)
  await draft.getByLabel("Symbol", {exact: true}).fill("narrow")
  await draft
    .getByLabel("Description", {exact: true})
    .fill("A description long enough to run past one line on a narrow phone screen.")
  await draft.getByLabel("Website", {exact: true}).fill("https://example.test/a-deliberately-long-draft-address")
  await draft.getByLabel("Image", {exact: true}).fill("https://example.test/a-deliberately-long-draft-image.png")
  await draft.getByLabel("Immutable treasury recipient", {exact: true}).fill(draftTreasury)
  await draft.getByLabel("Required raise in REGENT", {exact: true}).fill("1000.5")
  await draft.getByRole("button", {name: "Save draft"}).click()

  const card = page.locator("#launch-drafts article").filter({hasText: uniqueName})
  await expect(card).toBeVisible()

  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390)
  expect(
    await page.evaluate(() => {
      const scroller = document.querySelector("#app-shell-scroller")!
      return scroller.scrollWidth - scroller.clientWidth
    }),
  ).toBeLessThanOrEqual(0)

  const escapes = await page.locator("#autolaunch-create *").evaluateAll(nodes =>
    nodes
      .map(node => node.getBoundingClientRect())
      .filter(box => box.width > 0 && (box.left < -0.5 || box.right > 390.5))
      .length,
  )
  expect(escapes).toBe(0)

  // The full address stays on screen across more than one line rather than being
  // clipped or shortened.
  const treasury = card.locator(".autolaunch-draft-review dd").filter({hasText: draftTreasury})
  await expect(treasury).toHaveText(draftTreasury)

  const wrapping = await treasury.evaluate(element => {
    const range = document.createRange()
    range.selectNodeContents(element)
    return {lines: range.getClientRects().length, clipped: element.scrollWidth - element.clientWidth}
  })

  expect(wrapping.lines).toBeGreaterThan(1)
  expect(wrapping.clipped).toBeLessThanOrEqual(0)
})


test("Formation keeps one in-shell heading and an exact inactive Nous handoff", async ({page}) => {
  const requests: string[] = []
  page.on("request", request => requests.push(request.url()))

  await page.goto("/formation")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.getByRole("heading")).toHaveCount(1)
  await expect(
    page.getByRole("heading", {level: 1, name: "Regent runs best on Hermes"}),
  ).toBeVisible()
  await expect(
    page.getByText("Create and manage your Regent as a Hermes agent in Nous Portal."),
  ).toBeVisible()

  const portal = page.getByRole("link", {name: "Open Nous Portal"})
  await expect(portal).toHaveAttribute("href", "https://portal.nousresearch.com/cloud")
  await expect(portal).toHaveAttribute("target", "_blank")
  await expect(portal).toHaveAttribute("rel", "noopener noreferrer")
  await expect(
    page.getByText(
      "Nous Portal opens in a new tab. Your Hermes agent can complete Autolaunch in their cloud runtime.",
    ),
  ).toBeVisible()

  await expect(page.locator("#formation form")).toHaveCount(0)
  await expect(page.locator("#formation button")).toHaveCount(0)
  await expect(
    page.locator("#formation [phx-click], #formation [phx-submit]"),
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

    let reachedByTab = false

    for (let press = 0; press < 30 && !reachedByTab; press += 1) {
      await page.keyboard.press("Tab")
      reachedByTab = await page.evaluate(
        () => document.activeElement?.id === "formation-nous-portal-link",
      )
    }

    expect(reachedByTab, `${viewport.width}x${viewport.height}`).toBe(true)
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

  // With nothing saved the server renders the dark theme, and the switch says so
  // before it is touched.
  const toggle = page.locator("#theme-control [data-theme-toggle]")
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await expect(toggle).toHaveAttribute("aria-pressed", "false")
  await expect(toggle).toHaveAttribute(
    "aria-label",
    "Color theme: Dark. Activate Light theme.",
  )
  await expect(toggle.locator("[data-theme-toggle-state]")).toHaveText("Dark theme active")

  await toggle.click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(toggle).toHaveAttribute("aria-pressed", "true")
  await expect(toggle.locator("[data-theme-toggle-state]")).toHaveText("Light theme active")

  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "light")
  await expect(toggle).toHaveAttribute("aria-pressed", "true")

  await toggle.click()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await page.reload()
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark")
  await context.close()
})

for (const width of [320, 390]) {
  test(`${width}px drawer contains focus and cleans up every close path`, async ({page}) => {
    await page.setViewportSize({width, height: 720})
    await page.goto("/app")
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
    const destination = sidebar.locator('a[href]:not([href="/app"])').first()
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
    await page.goto("/app")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      viewport.width,
    )
  }
})
