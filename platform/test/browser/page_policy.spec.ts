import {expect, test} from "./support/offline"

// PAGE_POLICY: every kind of page works inside its content security policy. A
// refusal means a picture, video, script or connection the page needs is
// blocked. One page stands for each kind: the docs and About, the legal pages,
// the account pages with Pair and Names, the Redeem pages and the product pages
// each share one layout, and Cloak has its own.
test("[R14] no page is refused anything by its security policy", async ({page}) => {
  await page.addInitScript(() => {
    const refused: string[] = []
    ;(window as unknown as {refused: string[]}).refused = refused
    document.addEventListener("securitypolicyviolation", event =>
      refused.push(`${event.effectiveDirective} ${event.blockedURI}`),
    )
  })

  const refusals: string[] = []
  const collect = async (label: string) => {
    const found = await page.evaluate(() => (window as unknown as {refused: string[]}).refused)
    refusals.push(...found.map(refusal => `${label}: ${refusal}`))
  }

  for (const path of ["/", "/articles", "/docs", "/privacy", "/app", "/stake", "/redeem/gallery", "/account",
    "/autolaunch", "/cloak", "/no-such-page"]) {
    await page.goto(path)
    await page.waitForLoadState("networkidle")
    await collect(path)
  }

  await page.goto("/stake")
  await page.getByRole("button", {name: /sign in/i}).first().click()
  await page.waitForLoadState("networkidle")
  await collect("/stake after pressing sign in")

  expect(refusals).toEqual([])
})
