import {expect, test, type Page} from "./support/offline"
import {installAuthenticatedPrivy} from "./support/authenticated_privy"

// The Agent Message button on /agents (topic agents), made from ash-template's
// agent_message.spec.ts. At each width its dialog's two texts fit the screen and
// copy exactly what they show, and Escape closes it. Signed out it has only the
// texts; a signed-in person leaves a message from its form and sees the receipt,
// after an empty message is refused when the field is left.
const widths = [1280, 390, 320]

function watch(page: Page) {
  const errors: string[] = []
  page.on("pageerror", error => errors.push(error.message))
  return {expect: async () => expect(errors).toEqual([])}
}

async function openDialog(page: Page) {
  const dialog = page.getByRole("dialog", {name: "Agent Message"})
  await expect(dialog).toBeHidden()
  await page.getByRole("button", {name: "Agent Message"}).click()
  await expect(dialog).toBeVisible()
  return dialog
}

for (const width of widths) {
  test(`at ${width}, the texts copy and the window has no form signed out`, async ({page, context}) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"])
    await page.setViewportSize({width, height: 900})
    const problems = watch(page)
    await page.goto("/agents")
    const dialog = await openDialog(page)

    const texts = dialog.locator(".agent-message__text")
    await expect(texts).toHaveCount(2)
    for (const text of await texts.all()) {
      expect(await text.locator("pre").evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)

    const cli = texts.first()
    await cli.getByRole("button", {name: "Copy"}).click()
    await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe(
      await cli.locator("code").textContent(),
    )
    expect(await page.evaluate(() => navigator.clipboard.readText())).toContain(
      "regents protocol messages leave agents",
    )

    await expect(dialog.locator("#agents-message-person-form")).toHaveCount(0)
    await page.keyboard.press("Escape")
    await expect(dialog).toBeHidden()
    await problems.expect()
  })

  test(`at ${width}, a signed-in person leaves a message and sees its receipt`, async ({page}) => {
    await page.setViewportSize({width, height: 900})
    const problems = watch(page)
    const auth = await installAuthenticatedPrivy(page, "valid")
    await auth.establishLocalSession()
    await page.goto("/agents")
    const dialog = await openDialog(page)

    const form = dialog.locator("#agents-message-person-form")
    await expect(page.locator(".phx-connected:has(#agents-message-person-form)").first()).toBeAttached()
    const body = form.getByRole("textbox", {name: "Message", exact: true})
    const replyTo = form.getByRole("textbox", {name: "Reply to"})
    await body.fill("x")
    await body.fill("")
    await replyTo.focus()
    await expect(body).toHaveAttribute("aria-invalid", "true")

    await body.fill("The Agents page shows an old picture.")
    await replyTo.fill("walk@example.com")
    await form.getByRole("button", {name: "Send"}).click()
    const receipt = dialog.locator("#agents-message-person-receipt")
    await expect(receipt).toBeVisible()
    await expect(receipt.locator("code")).toHaveText(/^[0-9a-f-]{36}$/)
    await expect(body).toHaveValue("")
    await expect(dialog).toBeVisible()
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await problems.expect()
  })
}
