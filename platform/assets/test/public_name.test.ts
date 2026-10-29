// Invariant: Save on the Account page's Public Display Name writes the name to
// the profile it just read, making that profile from the sign-in only when the
// person has none, and never writes after a read or a profile-making that failed.
// Every step of one save belongs to one person: a switch of account part way
// through writes nothing (R-20261018-first-save-switch, found by the security
// review of 18 Oct and checked through the page's own save path after Sentinel's
// read of 19 Oct). A save waiting its turn belongs to the person signed in at its
// press, so a switch of account before it starts writes nothing
// (R-20261019-queued-save-switch, found by Sentinel's read of 19 Oct). Two quick
// presses keep the name pressed last
// (R-20261018-two-quick-saves, found by the breaker review of 18 Oct), and a
// save that fails outright never leaves the form busy.
import {expect, it, vi} from "vitest"
import {createProfileClient} from "../vendor/regent_identity/profile_client.mjs"
import {mountProfile, saveName} from "../vendor/regent_ui/profile.mjs"
import type {ProfileAction, ProfileResult} from "../vendor/regent_ui/profile.mjs"

vi.mock("@privy-io/react-auth", () => ({}))
vi.mock("react-dom/client", () => ({}))

const {oneSignIn} = await import("../js/privy_bridge")
const {createLazyAuthLoader} = await import("../js/auth_lazy")

const profile = (id: string, name: string | null = null): ProfileResult =>
  ({ok: true, status: 200, body: {profile: {profile_id: id, display_name: name}}})
const refused = (status: number, code: string): ProfileResult =>
  ({ok: false, status, body: {error: {code}}})

function server(answers: Record<string, ProfileResult>) {
  const calls: unknown[][] = []
  const action: ProfileAction = async (operation, input, options) => {
    calls.push([operation, input, options?.expectedProfileId])
    return answers[operation]
  }
  return {action, calls}
}

it("a first save makes the profile from the sign-in, then saves the name to it", async () => {
  const {action, calls} = server({
    get: refused(404, "profile_not_created"),
    sync: profile("p1"),
    update: profile("p1", "Ada"),
  })

  expect(await saveName(action, "Ada")).toMatchObject({ok: true, displayName: "Ada"})
  expect(calls).toEqual([
    ["get", {}, undefined],
    ["sync", {}, undefined],
    ["update", {display_name: "Ada"}, "p1"],
  ])
})

it("a later save changes the name on the profile it read", async () => {
  const {action, calls} = server({get: profile("p2", "Ada"), update: profile("p2", "Grace")})

  expect(await saveName(action, "Grace")).toMatchObject({ok: true, displayName: "Grace"})
  expect(calls.map(call => call[0])).toEqual(["get", "update"])
  expect(calls[1][2]).toBe("p2")
})

it("nothing is written without a current sign-in or a profile", async () => {
  const signedOut = server({get: {ok: false, status: null, error: {code: "authentication_required", outcome_unknown: false}}})
  expect(await saveName(signedOut.action, "Ada")).toMatchObject({ok: false})
  expect(signedOut.calls.map(call => call[0])).toEqual(["get"])

  const conflict = server({get: refused(404, "profile_not_created"), sync: refused(409, "identity_evidence_conflict")})
  expect(await saveName(conflict.action, "Ada")).toMatchObject({ok: false})
  expect(conflict.calls.map(call => call[0])).toEqual(["get", "sync"])
})

// regent_identity refuses a name holding hidden characters, such as a text-direction mark,
// with its own code (founder, 19 Oct); the person is told what to change.
it("a name the profile service refuses says what to change", async () => {
  const {action} = server({get: profile("p3", "Ada"), update: refused(422, "invalid_display_name")})

  expect(await saveName(action, "Ada‮gnp.exe")).toEqual({
    ok: false,
    message: "That name can't be used. Remove any hidden characters.",
  })
})

// The profile service as regent_identity serves it: each request acts for the
// person whose proof it carries, and refuses a subject that is not theirs.
function profileService() {
  const profiles = new Map<string, {profile_id: string; display_name: string | null}>()
  const writes: string[] = []
  const fetch = (async (path: string, init: RequestInit) => {
    const headers = init.headers as Record<string, string>
    const person = headers.authorization.replace("Bearer ", "")
    if (headers["x-privy-user-id"] !== person) return Response.json({error: {code: "identity_changed"}}, {status: 401})
    const mine = profiles.get(person)
    if (init.method === "GET") {
      return mine ? Response.json({profile: mine}) : Response.json({error: {code: "profile_not_created"}}, {status: 404})
    }
    writes.push(`${init.method} ${path} ${person}`)
    if (init.method === "POST") {
      const made = mine ?? {profile_id: `profile-${person}`, display_name: null}
      profiles.set(person, made)
      return Response.json({profile: made})
    }
    const expected = headers["x-regent-profile-id"]
    if (!mine || (expected && expected !== mine.profile_id)) {
      return Response.json({error: {code: "invalid_profile_update"}}, {status: 422})
    }
    mine.display_name = JSON.parse(String(init.body)).display_name
    return Response.json({profile: mine})
  }) as typeof globalThis.fetch
  return {fetch, profiles, writes}
}

// The sign-in the browser holds, which the person may switch at any moment.
function browser(first: string) {
  let person = first
  const proof = async () => ({
    accessToken: person, identityToken: person, subject: person, isCurrent: () => true,
  })
  return {switchTo: (next: string) => { person = next }, subject: () => person, proof}
}

// The page's own save path: the account loader starts the page's sign-in bridge,
// and the bridge opens a profile client for the person signed in at that moment,
// as privy_bridge.tsx does.
function pageLoader(service: ReturnType<typeof profileService>, signIn: ReturnType<typeof browser>) {
  return createLazyAuthLoader(async () => ({
    startPrivyBridge: async () => ({
      request: async () => {},
      openProfile: () =>
        createProfileClient({acquireProof: oneSignIn(signIn.subject(), signIn.proof), fetch: service.fetch}),
    }),
  }))
}

it("a switch of account after the first read saves nothing to either account", async () => {
  const service = profileService()
  const signIn = browser("did:a")
  const save = pageLoader(service, signIn).openProfile()
  const switching: ProfileAction = async (operation, input, options) => {
    const answer = await save(operation, input, options)
    if (operation === "get") signIn.switchTo("did:b")
    return answer
  }

  expect(await saveName(switching, "Ada")).toMatchObject({ok: false})
  expect(service.writes).toEqual([])
  expect(service.profiles.size).toBe(0)
})

it("the same person's first save still makes the profile and saves the name", async () => {
  const service = profileService()
  const save = pageLoader(service, browser("did:a")).openProfile()

  expect(await saveName(save, "Ada")).toMatchObject({ok: true, displayName: "Ada"})
  expect(service.profiles.get("did:a")?.display_name).toBe("Ada")
})

// The form as the page holds it: just what mountProfile reads and writes.
function form() {
  let submit: ((event: {preventDefault(): void}) => Promise<void>) | null = null
  const attributes = new Map<string, string>()
  const status = {textContent: ""}
  const name = {value: ""}
  const element = {
    elements: {namedItem: () => name},
    addEventListener: (_: string, listener: typeof submit) => { submit = listener },
    setAttribute: (key: string, value: string) => attributes.set(key, value),
    removeAttribute: (key: string) => attributes.delete(key),
  }
  const root = {querySelector: (selector: string) => selector === "[data-profile-form]" ? element : status}
  const press = (typed: string) => { name.value = typed; return submit!({preventDefault() {}}) }
  return {root: root as unknown as HTMLElement, attributes, status, name, press}
}

it("a save pressed before a switch of account, still waiting its turn, saves to neither account", async () => {
  const service = profileService()
  const signIn = browser("did:a")
  // The first save's change reaches the server, then the person switches account
  // while the second save waits for it.
  const switchDuringFirstWrite: typeof globalThis.fetch = async (input, init) => {
    if (init?.method === "PATCH") signIn.switchTo("did:b")
    return service.fetch(input, init)
  }
  const page = form()
  const loader = pageLoader({...service, fetch: switchDuringFirstWrite}, signIn)
  mountProfile(page.root, {openProfile: () => loader.openProfile(), onSaved: vi.fn()})

  await Promise.all([page.press("Ada"), page.press("Grace")])
  expect(service.profiles.get("did:a")?.display_name).toBe("Ada")
  expect(service.profiles.has("did:b")).toBe(false)
  expect(service.writes.filter(write => write.endsWith("did:b"))).toEqual([])
  expect(page.status.textContent).toBe("Sign in again to save your name.")
})

it("a save that fails outright says so and leaves the form ready", async () => {
  const page = form()
  const onSaved = vi.fn()
  mountProfile(page.root, {openProfile: () => { throw new Error("no sign-in loader") }, onSaved})

  await page.press("Ada")
  expect(page.attributes.has("aria-busy")).toBe(false)
  expect(page.status.textContent).not.toBe("")
  expect(onSaved).not.toHaveBeenCalled()
})

it("two quick saves keep the name pressed last, however slow the first is", async () => {
  const service = profileService()
  let firstRead = true
  const slowFirstRead: typeof globalThis.fetch = async (input, init) => {
    if (init?.method === "GET" && firstRead) {
      firstRead = false
      await new Promise(resolve => setTimeout(resolve, 20))
    }
    return service.fetch(input, init)
  }
  const page = form()
  const onSaved = vi.fn()
  const loader = pageLoader({...service, fetch: slowFirstRead}, browser("did:a"))
  mountProfile(page.root, {openProfile: () => loader.openProfile(), onSaved})

  await Promise.all([page.press("Ada"), page.press("Grace")])
  expect(service.profiles.get("did:a")?.display_name).toBe("Grace")
  expect(page.name.value).toBe("Grace")
  expect(page.attributes.has("aria-busy")).toBe(false)
  expect(onSaved.mock.calls).toEqual([["Grace"]])
})
