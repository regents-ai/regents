// Invariant: a signed-in person who presses Save on the Account page's Public
// Display Name has the name saved to their shared profile with the page's own
// sign-in, its session cookie and forms token, and it is still there after a
// reload. Privy plays no part in the save (R-20261114-name-save-session: saves on
// regents.sh were refused when the browser could not hand over fresh Privy
// tokens; the walk's browser never runs Privy here). It signs in as its own
// person, so the name it saves never shows in another test's account menu.
import {installAuthenticatedPrivy} from "./support/authenticated_privy"
import {expect, test} from "./support/offline"

// In order: both widths save the one name of this file's person.
test.describe.configure({mode: "default"})

for (const width of [1280, 390]) {
  test(`a signed-in person saves their Public Display Name and sees it after a reload (${width})`, async ({page}) => {
    const name = `Ada ${Date.now() % 100_000}`
    const errors: string[] = []
    page.on("pageerror", error => errors.push(error.message))
    await page.setViewportSize({width, height: 900})
    const auth = await installAuthenticatedPrivy(page, "public-name")
    await auth.establishLocalSession()

    await page.goto("/account")
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await expect(page.locator(".phx-connected").first()).toBeAttached()

    const form = page.locator("#account-profile")
    const field = form.getByRole("textbox", {name: "Public Display Name"})
    const change = page.waitForResponse(response =>
      response.request().method() === "PATCH" && new URL(response.url()).pathname === "/api/v1/profile")
    await field.fill(name)
    await form.getByRole("button", {name: "Save", exact: true}).click()

    expect((await change).status()).toBe(200)
    await expect(form.getByRole("status")).toHaveText("Saved.")

    await page.reload()
    await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
    await expect(field).toHaveValue(name)
    expect(errors).toEqual([])
  })
}
