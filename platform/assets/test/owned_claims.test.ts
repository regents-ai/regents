import {describe, expect, it, vi} from "vitest"
import {createClaimsClient} from "../js/owned_claims"

const proof = () => ({accessToken: "access-fixture", identityToken: "identity-fixture", subject: "did:privy:alice", isCurrent: () => true})
const claims = {claims: [{id: "9007199254740993", name: "alice.regent.eth", ens_name: null}], next: null}
const response = (body: unknown = claims) => new Response(JSON.stringify(body), {headers: {"content-type": "application/json"}})

describe("owned claims transport", () => {
  it("uses a fresh proof pair for each bounded read and never sends a session cookie", async () => {
    const acquireProof = vi.fn(async () => proof())
    const fetch = vi.fn(async () => response())
    const read = createClaimsClient({acquireProof, fetch})
    expect((await read()).body).toEqual(claims)
    await read("abc+/=")
    expect(acquireProof).toHaveBeenCalledTimes(2)
    expect(fetch.mock.calls[1]).toEqual(["/api/v1/claims?after=abc%2B%2F%3D", expect.objectContaining({
      credentials: "omit", redirect: "error", cache: "no-store",
      headers: expect.objectContaining({authorization: "Bearer access-fixture", "privy-id-token": "identity-fixture", "x-privy-user-id": "did:privy:alice"}),
    })])
  })

  it("rejects missing, expired-generation or changed identity proofs without exposing names", async () => {
    const fetch = vi.fn(async () => response())
    expect((await createClaimsClient({acquireProof: async () => null, fetch})()).ok).toBe(false)
    expect((await createClaimsClient({acquireProof: async () => ({...proof(), isCurrent: () => false}), fetch})()).ok).toBe(false)
    expect(fetch).not.toHaveBeenCalled()
    let current = true
    const read = createClaimsClient({acquireProof: async () => ({...proof(), isCurrent: () => current}), fetch: async () => {current = false; return response()}})
    const result = await read()
    expect(result.error?.code).toBe("identity_changed")
    expect(result.body).toBeUndefined()
  })

  it("cancels even if a provider or network read never settles", async () => {
    for (const stage of ["proof", "fetch", "body"]) {
      const abort = new AbortController()
      const never = new Promise<never>(() => {})
      const read = createClaimsClient({
        acquireProof: async () => stage === "proof" ? never : proof(),
        fetch: async () => stage === "fetch" ? never : new Response(new ReadableStream({pull: () => never})),
      })
      const pending = read(undefined, {signal: abort.signal})
      await new Promise(resolve => setTimeout(resolve, 0))
      abort.abort()
      expect((await pending).error?.code).toBe("cancelled")
    }
  })

  it("rejects invalid cursors before acquiring credentials and malformed or oversized responses", async () => {
    const acquireProof = vi.fn(async () => proof())
    const read = createClaimsClient({acquireProof, fetch: async () => response()})
    for (const cursor of ["", "a".repeat(2049)]) expect((await read(cursor)).error?.code).toBe("invalid_cursor")
    expect(acquireProof).not.toHaveBeenCalled()
    for (const body of [null, {claims: [null], next: null}, {claims: [{id: 9007199254740992}], next: null},
      {claims: Array(51).fill({}), next: null}, {claims: [], next: ""}, {claims: [{name: "a".repeat(262_144)}], next: null}]) {
      expect((await createClaimsClient({acquireProof, fetch: async () => response(body)})()).error?.code).toBe("claims_unavailable")
    }
  })
})
