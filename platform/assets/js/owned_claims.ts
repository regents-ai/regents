import type {ProfileAction} from "../vendor/regent_identity/profile_client.mjs"

type Proof = {accessToken: string; identityToken: string; subject: string; isCurrent: () => boolean}
export type ClaimsAction = (after?: string, options?: {signal?: AbortSignal}) => ReturnType<ProfileAction>

// A fixed, read-only product operation. Credentials never leave the lazy bridge.
export function createClaimsClient({acquireProof, fetch: request = fetch}: {
  acquireProof: (options: {signal: AbortSignal}) => Promise<Proof | null>
  fetch?: typeof fetch
}): ClaimsAction {
  return async (after, {signal} = {}) => {
    const failed = (code: string) => ({ok: false, status: null, error: {code, outcome_unknown: false}})
    if (after !== undefined && (typeof after !== "string" || !after.length || after.length > 2048)) return failed("invalid_cursor")
    const deadline = AbortSignal.any([AbortSignal.timeout(15_000), ...(signal ? [signal] : [])])
    let rejectAbort: () => void = () => {}
    try {
      deadline.throwIfAborted()
      const abort = new Promise<never>((_, reject) => {
        rejectAbort = () => reject(deadline.reason)
        deadline.addEventListener("abort", rejectAbort, {once: true})
      })
      const proof = await Promise.race([acquireProof({signal: deadline}), abort])
      deadline.throwIfAborted()
      if (!proof?.accessToken || !proof.identityToken || !proof.subject || !proof.isCurrent()) return failed("authentication_required")
      const response = await Promise.race([request("/api/v1/claims" + (after ? "?" + new URLSearchParams({after}) : ""), {
        credentials: "omit", redirect: "error", cache: "no-store", signal: deadline,
        headers: {accept: "application/json", authorization: `Bearer ${proof.accessToken}`,
          "privy-id-token": proof.identityToken, "x-privy-user-id": proof.subject},
      }), abort])
      const reader = response.body?.getReader()
      if (!reader) return failed("claims_unavailable")
      const chunks: Uint8Array[] = []
      let size = 0
      try {
        while (true) {
          const {done, value} = await Promise.race([reader.read(), abort])
          deadline.throwIfAborted()
          if (done) break
          size += value.byteLength
          if (size > 262_144) throw new Error("claims_response_too_large")
          chunks.push(value)
        }
      } finally { void reader.cancel().catch(() => {}); reader.releaseLock() }
      const bytes = new Uint8Array(size)
      let offset = 0
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
      const body = JSON.parse(new TextDecoder().decode(bytes))
      if (!proof.isCurrent()) return failed("identity_changed")
      if (response.ok && (!body || !Array.isArray(body.claims) || body.claims.length > 50 ||
          !body.claims.every((claim: unknown) => claim !== null && typeof claim === "object" &&
            !Array.isArray(claim) && Object.values(claim).every(value => value === null || typeof value === "string")) ||
          !(body.next === null || (typeof body.next === "string" && body.next.length > 0 && body.next.length <= 2048)))) return failed("claims_unavailable")
      return {ok: response.ok, status: response.status, body}
    } catch { return failed(signal?.aborted ? "cancelled" : "claims_unavailable") }
    finally { deadline.removeEventListener("abort", rejectAbort) }
  }
}

export function mountOwnedClaims(root: HTMLElement, read: ClaimsAction): () => void {
  const win = root.ownerDocument.defaultView!
  const list = root.querySelector<HTMLElement>("[data-claims-list]")!
  const status = root.querySelector<HTMLElement>("[data-claims-status]")!
  const load = root.querySelector<HTMLButtonElement>("[data-claims-load]")!
  const more = root.querySelector<HTMLButtonElement>("[data-claims-more]")!
  let active: AbortController | undefined
  let next: string | undefined
  let generation = 0
  const clear = () => {
    generation += 1
    active?.abort()
    active = undefined
    list.replaceChildren()
    next = undefined
    more.hidden = true
    status.textContent = "Load names linked to your verified wallets."
  }
  const render = (claim: Record<string, unknown>) => {
    const item = root.ownerDocument.createElement("li")
    const name = root.ownerDocument.createElement("strong")
    name.textContent = String(claim.name ?? "Recorded name")
    const details = root.ownerDocument.createElement("details")
    details.className = "rg-disclosure"
    const summary = root.ownerDocument.createElement("summary")
    const state = root.ownerDocument.createElement("span")
    state.textContent = String(claim.status ?? "Recorded")
    const chevron = root.ownerDocument.createElement("span")
    chevron.className = "rg-chevron"
    chevron.textContent = "›"
    chevron.setAttribute("aria-hidden", "true")
    summary.append(state, chevron)
    const facts = root.ownerDocument.createElement("dl")
    facts.className = "rg-disclosure-body"
    details.append(summary)
    for (const [label, value] of [["ENS name", claim.ens_name], ["Owner", claim.owner_address],
      ["Claimed", claim.claimed_at], ["Transaction", claim.transaction],
      ["ENS transaction", claim.ens_transaction], ["ENS assigned", claim.ens_assigned_at]]) {
      if (value == null) continue
      const term = root.ownerDocument.createElement("dt")
      const definition = root.ownerDocument.createElement("dd")
      term.textContent = String(label)
      definition.textContent = String(value)
      facts.append(term, definition)
    }
    details.append(facts)
    item.append(name, details)
    list.append(item)
  }
  const fetchPage = async (after?: string) => {
    if (!after) clear()
    active?.abort()
    const request = new AbortController()
    active = request
    const ownGeneration = generation
    status.textContent = "Loading names…"
    try {
      const result = await read(after, {signal: request.signal})
      if (request.signal.aborted || ownGeneration !== generation) return
      if (!result.ok) {
        status.textContent = result.status === 401 || result.error?.code === "authentication_required"
          ? "Sign in to view your names." : "Names could not be loaded. Try again."
        return
      }
      for (const claim of result.body.claims) render(claim)
      next = result.body.next ?? undefined
      more.hidden = !next
      status.textContent = list.children.length ? "Recorded history; transactions have not been reverified." : "No recorded names for these wallets."
    } catch {
      if (!request.signal.aborted && ownGeneration === generation) status.textContent = "Names could not be loaded. Try again."
    } finally { if (active === request) active = undefined }
  }
  // The initial lazy provider hydration can change identity while a user read is
  // waiting. Clear old data immediately and restart only that pending read.
  const identityChanged = () => {
    const pending = active !== undefined
    clear()
    if (pending) void fetchPage()
  }
  const reload = () => { void fetchPage() }
  const nextPage = () => { if (next) void fetchPage(next) }
  load.addEventListener("click", reload)
  more.addEventListener("click", nextPage)
  win.addEventListener("regent:profile-identity", identityChanged)
  win.addEventListener("regent:profile-link", identityChanged)
  win.addEventListener("pagehide", clear)
  return () => {
    clear()
    load.removeEventListener("click", reload)
    more.removeEventListener("click", nextPage)
    win.removeEventListener("regent:profile-identity", identityChanged)
    win.removeEventListener("regent:profile-link", identityChanged)
    win.removeEventListener("pagehide", clear)
  }
}
