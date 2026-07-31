import {
  PrivyProvider,
  type PrivyEvents,
  useLogin,
  useLinkAccount,
  usePrivy,
  useToken,
  useUnlinkFarcaster,
  useUnlinkOAuth,
  useWallets,
} from "@privy-io/react-auth"
import React from "react"
import {createRoot} from "react-dom/client"

import {
  browserSessionMutations,
  clearLocalSession,
  csrfToken,
  type AccountRequest,
  type IdentityRequest,
  type PrivyBridgeHandle,
  type SessionMutationCoordinator,
} from "./auth_lazy"
import {
  replaceConnectedEthereumWallets,
  type EthereumProvider,
} from "./wallet_actions/connected_wallet"

type AccountRequestHandlerOptions = {
  requestLogin: () => void
  providerLogout: () => Promise<void>
  synchronizeWallets: () => Promise<void>
}

export function createAccountRequestHandler({
  requestLogin,
  providerLogout,
  synchronizeWallets,
}: AccountRequestHandlerOptions): (request: AccountRequest) => Promise<void> {
  return async request => {
    if (request === "sign-in") {
      requestLogin()
      return
    }

    if (request === "sync") {
      await synchronizeWallets()
      return
    }

    await providerLogout()
  }
}

type IdentityRequestHandlerOptions = {
  linkX: () => void
  linkGithub: () => void
  linkFarcaster: () => void
  unlinkOAuth: (provider: "twitter" | "github", subject: string) => Promise<void>
  unlinkFarcaster: (fid: number) => Promise<void>
  refreshSession: () => Promise<void>
}

export function createIdentityRequestHandler({
  linkX,
  linkGithub,
  linkFarcaster,
  unlinkOAuth,
  unlinkFarcaster,
  refreshSession,
}: IdentityRequestHandlerOptions): (request: IdentityRequest) => Promise<void> {
  return async request => {
    if (request.action === "link") {
      if (request.provider === "x") linkX()
      if (request.provider === "github") linkGithub()
      if (request.provider === "farcaster") linkFarcaster()
      return
    }

    if (!request.subject) throw new Error("The connected account is unavailable.")

    if (request.provider === "farcaster") {
      const fid = Number(request.subject)
      if (!Number.isSafeInteger(fid) || fid <= 0) {
        throw new Error("The connected account is unavailable.")
      }
      await unlinkFarcaster(fid)
    } else {
      await unlinkOAuth(request.provider === "x" ? "twitter" : "github", request.subject)
    }

    await refreshSession()
  }
}

export {csrfToken}

export class LocalSessionEstablishmentError extends Error {
  constructor(readonly localSessionDropped: boolean) {
    super("Sign in could not be completed.")
  }
}

export async function createLocalSession(
  accessToken: string,
  fetcher: typeof fetch = fetch,
  sessionMutations: SessionMutationCoordinator = browserSessionMutations,
): Promise<{
  sessionChanged: boolean
  identityError?: "already-connected"
}> {
  return sessionMutations.establish(async signal => {
    const csrf = await csrfToken(fetcher, signal)
    if (signal.aborted) throw signal.reason
    const response = await fetcher("/auth/privy/session", {
      method: "POST",
      credentials: "same-origin",
      headers: {authorization: `Bearer ${accessToken}`, "x-csrf-token": csrf},
      signal,
    })
    if (signal.aborted) throw signal.reason
    if (!response.ok) throw new LocalSessionEstablishmentError(response.status === 401)
    const sessionChanged = response.headers.get("x-ash-session-changed")
    if (sessionChanged !== "true" && sessionChanged !== "false") {
      throw new LocalSessionEstablishmentError(false)
    }
    const identityError = response.headers.get("x-ash-identity-error")
    if (identityError && identityError !== "already-connected") {
      throw new LocalSessionEstablishmentError(false)
    }
    const verifiedIdentityError =
      identityError === "already-connected" ? identityError : undefined
    return {
      sessionChanged: sessionChanged === "true",
      ...(verifiedIdentityError ? {identityError: verifiedIdentityError} : {}),
    }
  })
}

type ProviderSessionReconcilerOptions = {
  clearSession: () => Promise<void>
  establishSession: (accessToken: string) => Promise<{sessionChanged: boolean}>
  getAccessToken: () => Promise<string | null>
  hasLinkedWallet: () => boolean
  providerAuthenticated: () => boolean
  reload: () => void
}

export function createProviderSessionReconciler({
  clearSession,
  establishSession,
  getAccessToken,
  hasLinkedWallet,
  providerAuthenticated,
  reload,
}: ProviderSessionReconcilerOptions): () => Promise<boolean> {
  return async () => {
    if (!providerAuthenticated()) {
      await clearSession()
      reload()
      return false
    }

    const accessToken = await getAccessToken()
    if (!accessToken) {
      await clearSession()
      reload()
      return false
    }

    try {
      const {sessionChanged} = await establishSession(accessToken)
      if (!hasLinkedWallet()) {
        await clearSession()
        reload()
        return false
      }
      if (sessionChanged) reload()
      return true
    } catch (error) {
      if (!(error instanceof LocalSessionEstablishmentError && error.localSessionDropped)) {
        await clearSession()
      }
      reload()
      throw error
    }
  }
}

type PrivySessionCompletionOptions = {
  fetcher?: typeof fetch
  localSessionNeeded: () => boolean
  reload: () => void
}

export function createPrivySessionCompletion({
  fetcher = fetch,
  localSessionNeeded,
  reload,
}: PrivySessionCompletionOptions): (accessToken: string) => Promise<void> {
  let inFlight: Promise<void> | null = null

  return accessToken => {
    if (!localSessionNeeded()) return Promise.resolve()
    if (inFlight) return inFlight

    const attempt = (async () => {
      if (accessToken.trim().length === 0) throw new Error("Sign in could not be completed.")
      await createLocalSession(accessToken, fetcher)
      reload()
    })()

    inFlight = attempt
    void attempt.catch(() => {
      if (inFlight === attempt) inFlight = null
    })

    return attempt
  }
}

export function createPrivyTokenCallbacks(
  completeLogin: (accessToken: string) => Promise<void>,
) {
  return {
    onAccessTokenGranted: ({accessToken}: {accessToken: string}) =>
      completeLogin(accessToken).catch(() => undefined),
    onAccessTokenRemoved: () => undefined,
  } satisfies PrivyEvents["accessToken"]
}

export function createPrivyLoginCallbacks(
  getAccessToken: () => Promise<string | null>,
  completeLogin: (accessToken: string) => Promise<void>,
): PrivyEvents["login"] {
  return {
    onComplete: async () => {
      const accessToken = await getAccessToken()
      if (accessToken) await completeLogin(accessToken)
    },
  } satisfies PrivyEvents["login"]
}

export function createReadyLoginGate(login: () => void) {
  let ready = false
  let pending = false

  return {
    requestLogin() {
      if (ready) login()
      else pending = true
    },
    setReady(nextReady: boolean) {
      ready = nextReady
      if (!ready || !pending) return
      pending = false
      login()
    },
  }
}

type AccountBridgeProps = {
  publishRequestHandler: (
    requestHandler: PrivyBridgeHandle["request"],
    identityHandler: NonNullable<PrivyBridgeHandle["identity"]>,
    ready: boolean,
  ) => void
}

function AccountBridge({publishRequestHandler}: AccountBridgeProps) {
  const {authenticated, logout, ready} = usePrivy()
  const {wallets} = useWallets()
  const completeLogin = React.useMemo(
    () =>
      createPrivySessionCompletion({
        localSessionNeeded: () =>
          document.querySelector("#account-control [data-account-target='sign-in']") !== null,
        reload: () => window.location.reload(),
      }),
    [],
  )
  const tokenCallbacks = React.useMemo(
    () => createPrivyTokenCallbacks(completeLogin),
    [completeLogin],
  )
  const {getAccessToken} = useToken(tokenCallbacks)
  const notifyIdentityState = React.useCallback((error: string | null) => {
    window.dispatchEvent(
      new CustomEvent("ash:identity-state", {detail: {error}}),
    )
  }, [])
  const refreshIdentitySession = React.useCallback(async () => {
    const accessToken = await getAccessToken()
    if (!accessToken) throw new Error("The connection could not be verified.")
    const result = await createLocalSession(accessToken)
    notifyIdentityState(result.identityError ?? null)
  }, [getAccessToken, notifyIdentityState])
  const linkCallbacks = React.useMemo(
    () => ({
      onSuccess: () => void refreshIdentitySession().catch(() => notifyIdentityState("failed")),
      onError: () => notifyIdentityState("failed"),
    }),
    [notifyIdentityState, refreshIdentitySession],
  )
  const {linkTwitter, linkGithub, linkFarcaster} = useLinkAccount(linkCallbacks)
  const {unlink: unlinkOAuth} = useUnlinkOAuth()
  const {unlink: unlinkFarcasterAccount} = useUnlinkFarcaster()
  const loginCallbacks = React.useMemo(
    () => createPrivyLoginCallbacks(getAccessToken, completeLogin),
    [completeLogin, getAccessToken],
  )
  const {login} = useLogin(loginCallbacks)
  const loginGate = React.useMemo(() => createReadyLoginGate(login), [login])
  const walletSyncGeneration = React.useRef(0)
  const reconcileProviderSession = React.useMemo(
    () =>
      createProviderSessionReconciler({
        clearSession: () => browserSessionMutations.signOut(clearLocalSession),
        establishSession: createLocalSession,
        getAccessToken,
        hasLinkedWallet: () => wallets.length > 0,
        providerAuthenticated: () => authenticated,
        reload: () => window.location.reload(),
      }),
    [authenticated, getAccessToken, wallets.length],
  )

  React.useEffect(() => loginGate.setReady(ready), [loginGate, ready])

  React.useEffect(() => {
    if (!ready || !authenticated) return

    void getAccessToken().then(accessToken => {
      if (accessToken) void completeLogin(accessToken).catch(() => undefined)
    })
  }, [authenticated, completeLogin, getAccessToken, ready])

  const synchronizeWallets = React.useCallback(async () => {
    const generation = ++walletSyncGeneration.current
    if (!ready || !(await reconcileProviderSession())) {
      replaceConnectedEthereumWallets([])
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
      return
    }

    const entries = await Promise.all(
      wallets.map(
        async wallet =>
          [
            wallet.address.toLowerCase(),
            (await wallet.getEthereumProvider()) as EthereumProvider,
          ] as const,
      ),
    )
    if (walletSyncGeneration.current !== generation) return
    replaceConnectedEthereumWallets(entries)
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, [ready, reconcileProviderSession, wallets])

  React.useEffect(() => {
    void synchronizeWallets()
    return () => {
      walletSyncGeneration.current += 1
    }
  }, [synchronizeWallets])

  const requestHandler = React.useMemo(
    () =>
      createAccountRequestHandler({
        requestLogin: loginGate.requestLogin,
        providerLogout: logout,
        synchronizeWallets,
      }),
    [loginGate, logout, synchronizeWallets],
  )

  const identityHandler = React.useMemo(
    () =>
      createIdentityRequestHandler({
        linkX: linkTwitter,
        linkGithub,
        linkFarcaster,
        unlinkOAuth: async (provider, subject) => {
          await unlinkOAuth({provider, subject})
        },
        unlinkFarcaster: async fid => {
          await unlinkFarcasterAccount({fid})
        },
        refreshSession: refreshIdentitySession,
      }),
    [
      linkFarcaster,
      linkGithub,
      linkTwitter,
      refreshIdentitySession,
      unlinkFarcasterAccount,
      unlinkOAuth,
    ],
  )

  React.useEffect(
    () => publishRequestHandler(requestHandler, identityHandler, ready),
    [identityHandler, publishRequestHandler, ready, requestHandler],
  )

  return null
}

export function startPrivyBridge(): Promise<PrivyBridgeHandle> {
  const appId = document.querySelector<HTMLMetaElement>("meta[name='privy-app-id']")?.content
  if (!appId) return Promise.reject(new Error("Privy app is unavailable"))
  const host = document.createElement("div")
  host.hidden = true
  document.body.append(host)

  return new Promise(resolve => {
    let currentRequestHandler: PrivyBridgeHandle["request"] | null = null
    let currentIdentityHandler: PrivyBridgeHandle["identity"] | null = null
    let resolved = false
    const handle: PrivyBridgeHandle = {
      request(request) {
        return currentRequestHandler
          ? currentRequestHandler(request)
          : Promise.reject(new Error("Privy bridge is not ready"))
      },
      identity(request) {
        return currentIdentityHandler
          ? currentIdentityHandler(request)
          : Promise.reject(new Error("Privy bridge is not ready"))
      },
    }
    const publishRequestHandler: AccountBridgeProps["publishRequestHandler"] = (
      requestHandler,
      identityHandler,
      ready,
    ) => {
      currentRequestHandler = requestHandler
      currentIdentityHandler = identityHandler
      if (!ready || resolved) return
      resolved = true
      resolve(handle)
    }

    createRoot(host).render(
      <PrivyProvider appId={appId} config={{loginMethods: ["wallet"]}}>
        <AccountBridge publishRequestHandler={publishRequestHandler} />
      </PrivyProvider>,
    )
  })
}
