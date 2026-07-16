export type AccountRequest = "sign-in" | "sign-out" | "sync"

export type PrivyBridgeHandle = {
  request: (request: AccountRequest) => Promise<void>
}

export type PrivyBridgeModule = {
  startPrivyBridge: () => Promise<PrivyBridgeHandle>
}

type PrivyBridgeImporter = () => Promise<PrivyBridgeModule>

type BrowserPrivyBridgeImporterOptions = {
  bridgeSource: string | null
  runtimeImport?: (url: string) => Promise<PrivyBridgeModule>
  currentOrigin?: string
}

type AccountAuthInstallOptions = {
  clearSession?: () => Promise<void>
  providerSignOutTimeoutMs?: number
  reload?: () => void
  sessionMutations?: SessionMutationCoordinator
  signedInStartupTimeoutMs?: number
}

const defaultProviderSignOutTimeoutMs = 1_500
const defaultSignedInStartupTimeoutMs = 5_000

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
) {
  let handle: PrivyBridgeHandle | null = null
  let preparing: Promise<void> | null = null
  let pending: AccountRequest | null = null
  let delivering: {request: AccountRequest; promise: Promise<void>} | null = null

  const deliverPending = (): Promise<void> => {
    if (!handle) return Promise.resolve()
    if (delivering) {
      return pending === null || delivering.request === pending
        ? delivering.promise
        : delivering.promise.then(deliverPending, deliverPending)
    }
    if (!pending) return Promise.resolve()

    const request = pending
    pending = null
    const attempt = handle.request(request)
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
        return module.startPrivyBridge()
      })
      .then(readyHandle => {
        if (!readyHandle || typeof readyHandle.request !== "function") {
          throw new Error("Privy bridge handle is invalid")
        }
        handle = readyHandle
        preparing = null
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
      if (delivering?.request === request && pending === null) return delivering.promise
      pending = request
      if (handle) return deliverPending()
      return preparing ?? prepare()
    },
  }
}

export function installAccountAuthLazyLoader(
  documentRoot: Document = document,
  importer?: PrivyBridgeImporter,
  {
    clearSession = clearLocalSession,
    providerSignOutTimeoutMs = defaultProviderSignOutTimeoutMs,
    reload = () => window.location.reload(),
    sessionMutations = browserSessionMutations,
    signedInStartupTimeoutMs = defaultSignedInStartupTimeoutMs,
  }: AccountAuthInstallOptions = {},
): () => void {
  const bridgeSource = documentRoot.querySelector<HTMLMetaElement>(
    "meta[name='privy-bridge-src']",
  )?.content
  const loader = createLazyAuthLoader(
    importer ?? createBrowserPrivyBridgeImporter({bridgeSource: bridgeSource ?? null}),
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

    const attempt = (async () => {
      try {
        await sessionMutations.signOut(clearSession)
      } catch {
        showLoadFailure("sign-out")
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
        reload()
      }
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

      if (!userSignOutStarted) reload()
    })
  }

  documentRoot.addEventListener("click", onClick)
  if (documentRoot.querySelector("#account-control [data-account-target='sign-out']")) {
    reconcileSignedInStartup()
  }
  return () => documentRoot.removeEventListener("click", onClick)
}
