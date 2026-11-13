// Invariant: a signed-in person who presses Save on the Account page's Public
// Display Name has the name saved to their shared profile. One save needs one
// answer from Privy: a Privy refusal after the save has read the profile does
// not lose the name (R-20261112-name-save, found when the founder's save on
// regents.sh read the profile and never sent the change).
import {identityTokenFor, matchesAuthenticatedPrivyBridgeUrl} from "./support/authenticated_privy"
import {expect, test} from "./support/offline"
import {accessToken, identityToken, installPrivyService} from "./support/privy_service"

test("a signed-in person saves their Public Display Name", async ({page}) => {
  const name = `Ada ${Date.now() % 100_000}`
  await installPrivyService(page)

  const csrf = await page.request.get("/auth/csrf")
  const origin = new URL(csrf.url()).origin
  const {csrf_token: csrfToken} = await csrf.json()
  const session = await page.request.post("/auth/privy/session", {
    headers: {authorization: "Bearer valid", "privy-id-token": identityTokenFor("valid"), "x-csrf-token": csrfToken},
    data: {},
  })
  expect(session.status()).toBe(200)
  // The person already has a profile, so the save reads it and changes the name.
  const proof = () => ({authorization: `Bearer ${accessToken()}`, "privy-id-token": identityToken()})
  const made = await page.request.post("/api/v1/profile/sync", {headers: proof()})
  expect(made.status()).toBe(200)

  // The sign-in bridge arrives only once Save is pressed, so the save waits for
  // Privy to start, as it does on a slow connection.
  let pressSave!: () => void
  const pressed = new Promise<void>(resolve => { pressSave = resolve })
  await page.route(url => matchesAuthenticatedPrivyBridgeUrl(url.href, origin), async route => {
    await pressed
    await route.continue()
  })

  await page.goto("/account")
  await expect(page.locator("#app-shell")).toHaveAttribute("data-behavior-ready", "true")
  await expect(page.locator(".phx-connected").first()).toBeAttached()

  const form = page.locator("#account-profile")
  const change = page.waitForResponse(response =>
    response.request().method() === "PATCH" && new URL(response.url()).pathname === "/api/v1/profile")
  await form.getByRole("textbox", {name: "Public Display Name"}).fill(name)
  await form.getByRole("button", {name: "Save", exact: true}).click()
  pressSave()

  expect((await change).status()).toBe(200)
  await expect(form.getByRole("status")).toHaveText("Saved.")

  const kept = await page.request.get("/api/v1/profile", {headers: proof()})
  expect((await kept.json()).profile.display_name).toBe(name)
})
