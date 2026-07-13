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

const bridgePath = /^\/assets\/js\/privy_bridge(?:-[a-f0-9]{32})?\.js$/

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
    if (!handle || !pending) return Promise.resolve()
    if (delivering) {
      return delivering.request === pending
        ? delivering.promise
        : delivering.promise.then(deliverPending)
    }

    const request = pending
    pending = null
    const attempt = handle
      .request(request)
      .finally(() => {
        if (delivering?.promise === attempt) delivering = null
      })
      .then(deliverPending)
    delivering = {request, promise: attempt}
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
): () => void {
  const appId = documentRoot.querySelector<HTMLMetaElement>("meta[name='privy-app-id']")?.content
  if (!appId) return () => undefined

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
  const request = (accountRequest: AccountRequest) => {
    clearStatus()
    void loader
      .request(accountRequest)
      .then(clearStatus)
      .catch(() => showLoadFailure(accountRequest))
  }
  const onClick = (event: Event) => {
    const target = event.target instanceof Element ? event.target : null
    const accountTarget = target?.closest<HTMLElement>("[data-account-target]")?.dataset
      .accountTarget

    if (accountTarget === "sign-in" || accountTarget === "sign-out") {
      request(accountTarget)
    }
  }

  documentRoot.addEventListener("click", onClick)
  if (documentRoot.querySelector("#account-control [data-account-target='identity']")) {
    request("sync")
  }
  return () => documentRoot.removeEventListener("click", onClick)
}
