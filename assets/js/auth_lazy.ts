export type AccountRequest = "sign-in" | "sign-out" | "sync"

export type IdentityProvider = "x" | "github" | "farcaster"

export type IdentityRequest = {
  action: "link" | "unlink"
  provider: IdentityProvider
  subject?: string
}

export type PrivyBridgeHandle = {
  request: (request: AccountRequest) => Promise<void>
  identity?: (request: IdentityRequest) => Promise<void>
  finishSignOutOnly?: () => void
}

export type PrivyBridgeStartupOptions = {
  mode?: "ordinary" | "sign-out-only"
}

export type PrivyBridgeModule = {
  startPrivyBridge: (options?: PrivyBridgeStartupOptions) => Promise<PrivyBridgeHandle>
}

type PrivyBridgeImporter = () => Promise<PrivyBridgeModule>

type BrowserPrivyBridgeImporterOptions = {
  bridgeSource: string | null
  runtimeImport?: (url: string) => Promise<PrivyBridgeModule>
  currentOrigin?: string
}

type AccountAuthInstallOptions = {
  clearSession?: () => Promise<void>
  handoffStorage?: Pick<Storage, "getItem" | "setItem" | "removeItem">
  now?: () => number
  providerSignOutTimeoutMs?: number
  sessionMutations?: SessionMutationCoordinator
  signedInStartupTimeoutMs?: number
}

const defaultProviderSignOutTimeoutMs = 1_500
const defaultSignedInStartupTimeoutMs = 5_000
const signOutHandoffKey = "regent:privy-sign-out-handoff:v1"
const signOutHandoffMaxAgeMs = 30_000
const consumedHandoffDocuments = new WeakSet<Document>()

const bridgePath = /^\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js$/

export async function csrfToken(
  fetcher: typeof fetch = fetch,
  signal?: AbortSignal,
): Promise<string> {
  const response = await fetcher("/auth/csrf", {
    credentials: "same-origin",
    ...(signal ? {signal} : {}),
  })
  if (!response.ok) throw new Error("Unable to start a secure session change.")
  const body = (await response.json()) as {csrf_token?: unknown}
  if (typeof body.csrf_token !== "string" || body.csrf_token.length === 0) {
    throw new Error("Unable to start a secure session change.")
  }
  return body.csrf_token
}

export async function clearLocalSession(fetcher: typeof fetch = fetch): Promise<void> {
  const csrf = await csrfToken(fetcher)
  const response = await fetcher("/auth/privy/session", {
    method: "DELETE",
    credentials: "same-origin",
    headers: {"x-csrf-token": csrf},
  })
  if (!response.ok) throw new Error("Sign out could not be completed.")
}

type SignOutHandoff = {version: 1; issuedAtMs: number}

function handoffStorageOrNull(
  storage?: Pick<Storage, "getItem" | "setItem" | "removeItem">,
) {
  if (storage) return storage
  try {
    return window.sessionStorage
  } catch {
    return null
  }
}

export function writeSignOutHandoff(
  storage: Pick<Storage, "getItem" | "setItem" | "removeItem"> | null,
  issuedAtMs: number,
): boolean {
  if (!storage || !Number.isInteger(issuedAtMs)) return false
  const value = JSON.stringify({version: 1, issuedAtMs} satisfies SignOutHandoff)

  try {
    storage.setItem(signOutHandoffKey, value)
  } catch {
    return false
  }

  try {
    return storage.getItem(signOutHandoffKey) === value
  } catch {
    return false
  }
}

export function clearSignOutHandoff(
  storage: Pick<Storage, "getItem" | "setItem" | "removeItem"> | null,
): void {
  if (!storage) return

  try {
    storage.removeItem(signOutHandoffKey)
  } catch {
    try {
      storage.setItem(signOutHandoffKey, "")
    } catch {
      return
    }
  }

  try {
    if (storage.getItem(signOutHandoffKey) !== null) {
      storage.setItem(signOutHandoffKey, "")
      void storage.getItem(signOutHandoffKey)
    }
  } catch {
    // Cleanup is best-effort and must never mask the local sign-out failure.
  }
}

function validSignOutHandoff(value: string, nowMs: number): boolean {
  try {
    const parsed = JSON.parse(value) as unknown
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return false
    const record = parsed as Record<string, unknown>
    if (Object.keys(record).sort().join(",") !== "issuedAtMs,version") return false
    if (record.version !== 1 || !Number.isInteger(record.issuedAtMs)) return false
    const issuedAtMs = record.issuedAtMs as number
    return issuedAtMs <= nowMs && nowMs - issuedAtMs <= signOutHandoffMaxAgeMs
  } catch {
    return false
  }
}

export function consumeSignOutHandoff(
  documentRoot: Document,
  storage: Pick<Storage, "getItem" | "setItem" | "removeItem"> | null,
  nowMs: number,
): boolean {
  if (consumedHandoffDocuments.has(documentRoot)) return false
  consumedHandoffDocuments.add(documentRoot)
  if (!storage) return false

  let captured: string | null
  try {
    captured = storage.getItem(signOutHandoffKey)
  } catch {
    return false
  }

  try {
    storage.removeItem(signOutHandoffKey)
  } catch {
    return false
  }

  try {
    if (storage.getItem(signOutHandoffKey) !== null) return false
  } catch {
    return false
  }

  return captured !== null && validSignOutHandoff(captured, nowMs)
}

export async function proveAnonymousSession(fetcher: typeof fetch = fetch): Promise<boolean> {
  try {
    const response = await fetcher("/auth/session", {
      credentials: "same-origin",
      redirect: "error",
    })
    if (!response.ok || response.redirected) return false
    const body = (await response.json()) as unknown
    return Boolean(
      body &&
        typeof body === "object" &&
        (body as {authenticated?: unknown}).authenticated === false,
    )
  } catch {
    return false
  }
}

export type SessionMutationCoordinator = {
  establish<T>(mutation: (signal: AbortSignal) => Promise<T>): Promise<T>
  signOut(clearSession: () => Promise<void>): Promise<void>
}

type SessionMutationCoordinatorOptions = {
  cancellationWaitMs?: number
}

const defaultCancellationWaitMs = 250

function cancelledSessionEstablishment(signal: AbortSignal): never {
  throw signal.reason ?? new Error("Local sign out has already started.")
}

function settleWithin(promise: Promise<void>, timeoutMs: number): Promise<void> {
  return new Promise(resolve => {
    let timeout: ReturnType<typeof globalThis.setTimeout> | undefined
    const finish = () => {
      if (timeout !== undefined) globalThis.clearTimeout(timeout)
      resolve()
    }
    timeout = globalThis.setTimeout(finish, timeoutMs)
    void promise.then(finish, finish)
  })
}

export function createSessionMutationCoordinator({
  cancellationWaitMs = defaultCancellationWaitMs,
}: SessionMutationCoordinatorOptions = {}): SessionMutationCoordinator {
  let establishmentTail: Promise<void> = Promise.resolve()
  let signingOut = false
  let signOutAttempt: Promise<void> | null = null
  const activeEstablishments = new Set<AbortController>()

  return {
    establish<T>(mutation: (signal: AbortSignal) => Promise<T>): Promise<T> {
      if (signingOut) {
        return Promise.reject(new Error("Local sign out has already started."))
      }

      const controller = new AbortController()
      activeEstablishments.add(controller)
      const attempt = establishmentTail.then(async () => {
        if (signingOut || controller.signal.aborted) {
          cancelledSessionEstablishment(controller.signal)
        }
        const value = await mutation(controller.signal)
        if (signingOut || controller.signal.aborted) {
          cancelledSessionEstablishment(controller.signal)
        }
        return value
      })
      const removeController = () => activeEstablishments.delete(controller)
      void attempt.then(removeController, removeController)
      establishmentTail = attempt.then(
        () => undefined,
        () => undefined,
      )
      return attempt
    },
    signOut(clearSession: () => Promise<void>): Promise<void> {
      if (signOutAttempt) return signOutAttempt
      signingOut = true
      activeEstablishments.forEach(controller => controller.abort())

      const attempt = settleWithin(establishmentTail, cancellationWaitMs).then(clearSession)
      signOutAttempt = attempt
      void attempt.catch(() => {
        if (signOutAttempt === attempt) signOutAttempt = null
      })
      return attempt
    },
  }
}

export const browserSessionMutations = createSessionMutationCoordinator()

function withinWindow<T>(
  attempt: Promise<T>,
  timeoutMs: number,
  timeoutMessage: string,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = globalThis.setTimeout(
      () => reject(new Error(timeoutMessage)),
      timeoutMs,
    )
    void attempt.then(
      value => {
        globalThis.clearTimeout(timeout)
        resolve(value)
      },
      error => {
        globalThis.clearTimeout(timeout)
        reject(error)
      },
    )
  })
}

function validatedBridgeUrl(bridgeSource: string | null, currentOrigin: string): URL | null {
  if (!bridgeSource) return null

  try {
    const candidate = new URL(bridgeSource, currentOrigin)
    const allowedQuery = candidate.search === "" || candidate.search === "?vsn=d"

    return candidate.origin === currentOrigin &&
      candidate.username === "" &&
      candidate.password === "" &&
      candidate.hash === "" &&
      allowedQuery &&
      bridgePath.test(candidate.pathname)
      ? candidate
      : null
  } catch {
    return null
  }
}

export function createBrowserPrivyBridgeImporter({
  bridgeSource,
  runtimeImport = url => import(url),
  currentOrigin = window.location.origin,
}: BrowserPrivyBridgeImporterOptions): PrivyBridgeImporter {
  let retryNumber = 0

  return async () => {
    const bridgeUrl = validatedBridgeUrl(bridgeSource, currentOrigin)
    if (!bridgeUrl) throw new Error("Privy bridge source is unavailable")

    bridgeUrl.searchParams.set("regent_retry", String(retryNumber))
    retryNumber += 1
    return runtimeImport(bridgeUrl.href)
  }
}

export function createLazyAuthLoader(
  importer: PrivyBridgeImporter,
  startupOptions: PrivyBridgeStartupOptions = {},
) {
  let state: "ordinary" | "handoff-preterminal" | "handoff-terminal" =
    startupOptions.mode === "sign-out-only" ? "handoff-preterminal" : "ordinary"
  let handle: PrivyBridgeHandle | null = null
  let preparing: Promise<void> | null = null
  let pending: AccountRequest | IdentityRequest | null = null
  let delivering: {
    request: AccountRequest | IdentityRequest
    promise: Promise<void>
  } | null = null

  const sameRequest = (
    first: AccountRequest | IdentityRequest,
    second: AccountRequest | IdentityRequest,
  ) =>
    typeof first === "string" || typeof second === "string"
      ? first === second
      : first.action === second.action &&
        first.provider === second.provider &&
        first.subject === second.subject

  const deliverPending = (): Promise<void> => {
    if (!handle) return Promise.resolve()
    if (delivering) {
      return pending === null || sameRequest(delivering.request, pending)
        ? delivering.promise
        : delivering.promise.then(deliverPending, deliverPending)
    }
    if (!pending) return Promise.resolve()

    const request = pending
    pending = null
    const attempt =
      typeof request === "string"
        ? handle.request(request)
        : handle.identity
          ? handle.identity(request)
          : Promise.reject(new Error("Privy identity bridge is not ready"))
    const settle = () => {
      if (delivering?.promise === attempt) delivering = null
      void deliverPending().catch(() => undefined)
    }
    delivering = {request, promise: attempt}
    void attempt.then(settle, settle)
    return attempt
  }

  const prepare = (): Promise<void> => {
    const attempt = importer()
      .then(module => {
        if (typeof module.startPrivyBridge !== "function") {
          throw new Error("Privy bridge module is invalid")
        }
        return startupOptions.mode
          ? module.startPrivyBridge(startupOptions)
          : module.startPrivyBridge()
      })
      .then(readyHandle => {
        if (!readyHandle || typeof readyHandle.request !== "function") {
          throw new Error("Privy bridge handle is invalid")
        }
        handle = readyHandle
        preparing = null
        if (state === "handoff-terminal") handle.finishSignOutOnly?.()
        return deliverPending()
      })

    preparing = attempt
    void attempt.catch(() => {
      if (preparing === attempt) preparing = null
    })
    return attempt
  }

  return {
    request(request: AccountRequest): Promise<void> {
      if (state === "handoff-preterminal" && request !== "sign-out") {
        return Promise.reject(new Error("Provider sign out is still in progress."))
      }
      if (state === "handoff-terminal") {
        if (request === "sign-out") return Promise.resolve()
        if (request === "sync") {
          return Promise.reject(new Error("Automatic reconciliation is disabled."))
        }
      }
      if (
        delivering &&
        sameRequest(delivering.request, request) &&
        pending === null
      ) {
        return delivering.promise
      }
      pending = request
      if (handle) return deliverPending()
      return preparing ?? prepare()
    },
    identity(request: IdentityRequest): Promise<void> {
      if (state === "handoff-preterminal") {
        return Promise.reject(new Error("Provider sign out is still in progress."))
      }
      if (
        delivering &&
        sameRequest(delivering.request, request) &&
        pending === null
      ) {
        return delivering.promise
      }
      pending = request
      if (handle) return deliverPending()
      return preparing ?? prepare()
    },
    finishHandoff(): void {
      if (state !== "handoff-preterminal") return
      state = "handoff-terminal"
      pending = null
      handle?.finishSignOutOnly?.()
    },
  }
}

export function installAccountAuthLazyLoader(
  documentRoot: Document = document,
  importer?: PrivyBridgeImporter,
  {
    clearSession = clearLocalSession,
    handoffStorage,
    now = () => Date.now(),
    providerSignOutTimeoutMs = defaultProviderSignOutTimeoutMs,
    sessionMutations = browserSessionMutations,
    signedInStartupTimeoutMs = defaultSignedInStartupTimeoutMs,
  }: AccountAuthInstallOptions = {},
): () => void {
  const storage = handoffStorageOrNull(handoffStorage)
  const consumedHandoff = consumeSignOutHandoff(documentRoot, storage, now())
  const bridgeSource = documentRoot.querySelector<HTMLMetaElement>(
    "meta[name='privy-bridge-src']",
  )?.content
  const loader = createLazyAuthLoader(
    importer ?? createBrowserPrivyBridgeImporter({bridgeSource: bridgeSource ?? null}),
    consumedHandoff ? {mode: "sign-out-only"} : {},
  )
  const clearStatus = () => {
    const status = documentRoot.querySelector<HTMLElement>("#account-auth-status")
    if (!status) return
    status.textContent = ""
    status.hidden = true
  }
  const showLoadFailure = (request: AccountRequest) => {
    const status = documentRoot.querySelector<HTMLElement>("#account-auth-status")
    if (!status) return
    status.textContent = {
      "sign-in": "Sign in couldn’t start. Try again.",
      "sign-out": "Sign out couldn’t finish. Try again.",
      sync: "Account connection couldn’t refresh. Try again.",
    }[request]
    status.hidden = false
  }
  const showProviderSignOutFailure = () => {
    const status = documentRoot.querySelector<HTMLElement>("#account-auth-status")
    if (!status) return
    status.textContent = "Signed out locally. Provider sign out couldn’t finish."
    status.hidden = false
  }
  const request = (accountRequest: AccountRequest) => {
    clearStatus()
    void loader
      .request(accountRequest)
      .then(clearStatus)
      .catch(() => showLoadFailure(accountRequest))
  }
  let signOutInFlight: Promise<void> | null = null
  let userSignOutStarted = false
  const signOut = () => {
    if (signOutInFlight) return
    userSignOutStarted = true
    clearStatus()
    writeSignOutHandoff(storage, now())

    const attempt = (async () => {
      try {
        await sessionMutations.signOut(clearSession)
      } catch {
        clearSignOutHandoff(storage)
        showLoadFailure("sign-out")
        return
      }
      clearStatus()
    })()

    signOutInFlight = attempt
    void attempt.finally(() => {
      if (signOutInFlight === attempt) signOutInFlight = null
    })
  }
  const onClick = (event: Event) => {
    const target = event.target instanceof Element ? event.target : null
    const accountTarget = target?.closest<HTMLElement>("[data-account-target]")?.dataset
      .accountTarget

    if (accountTarget === "sign-in") request("sign-in")
    if (accountTarget === "sign-out") signOut()
  }
  const onIdentityRequest = (event: Event) => {
    if (!(event instanceof CustomEvent) || !isIdentityRequest(event.detail)) return
    clearStatus()
    void loader
      .identity(event.detail)
      .then(clearStatus)
      .catch(() => showIdentityFailure())
  }
  const showIdentityFailure = () => {
    const status = documentRoot.querySelector<HTMLElement>("#account-auth-status")
    if (!status) return
    status.textContent = "That connection couldn’t be updated. Try again."
    status.hidden = false
  }

  const reconcileSignedInStartup = () => {
    clearStatus()
    void withinWindow(
      loader.request("sync"),
      signedInStartupTimeoutMs,
      "Provider session reconciliation did not become ready.",
    ).then(clearStatus, async () => {
      if (userSignOutStarted) return
      showLoadFailure("sync")

      try {
        await sessionMutations.signOut(clearSession)
      } catch {
        return
      }
    })
  }

  documentRoot.addEventListener("click", onClick)
  documentRoot.addEventListener("ash:identity-request", onIdentityRequest)
  if (consumedHandoff) {
    void proveAnonymousSession().then(async anonymous => {
      if (!anonymous) {
        loader.finishHandoff()
        return
      }

      try {
        await withinWindow(
          loader.request("sign-out"),
          providerSignOutTimeoutMs,
          "Provider sign out did not become ready.",
        )
        clearStatus()
      } catch {
        showProviderSignOutFailure()
      } finally {
        loader.finishHandoff()
      }
    })
  } else if (documentRoot.querySelector("#account-control [data-account-target='sign-out']")) {
    reconcileSignedInStartup()
  }
  return () => {
    documentRoot.removeEventListener("click", onClick)
    documentRoot.removeEventListener("ash:identity-request", onIdentityRequest)
  }
}

function isIdentityRequest(value: unknown): value is IdentityRequest {
  if (!value || typeof value !== "object") return false
  const request = value as Partial<IdentityRequest>
  return (
    (request.action === "link" || request.action === "unlink") &&
    (request.provider === "x" ||
      request.provider === "github" ||
      request.provider === "farcaster") &&
    (request.subject === undefined || typeof request.subject === "string")
  )
}
