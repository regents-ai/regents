import {
  PrivyProvider,
  type PrivyEvents,
  useLogin,
  usePrivy,
  useToken,
  useWallets,
} from "@privy-io/react-auth"
import React from "react"
import {createRoot} from "react-dom/client"

import type {AccountRequest, PrivyBridgeHandle} from "./auth_lazy"
import {
  replaceConnectedEthereumWallets,
  type EthereumProvider,
} from "./wallet_actions/connected_wallet"

type AccountRequestHandlerOptions = {
  requestLogin: () => void
  clearSession: () => Promise<void>
  providerLogout: () => Promise<void>
  reload: () => void
  synchronizeWallets: () => Promise<void>
}

export function createAccountRequestHandler({
  requestLogin,
  clearSession,
  providerLogout,
  reload,
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

    await clearSession()
    try {
      await providerLogout()
    } finally {
      reload()
    }
  }
}

export async function csrfToken(fetcher: typeof fetch = fetch): Promise<string> {
  const response = await fetcher("/auth/csrf", {credentials: "same-origin"})
  if (!response.ok) throw new Error("Unable to start a secure sign-in.")
  const body = (await response.json()) as {csrf_token?: unknown}
  if (typeof body.csrf_token !== "string" || body.csrf_token.length === 0) {
    throw new Error("Unable to start a secure sign-in.")
  }
  return body.csrf_token
}

export async function createLocalSession(
  accessToken: string,
  fetcher: typeof fetch = fetch,
): Promise<void> {
  const csrf = await csrfToken(fetcher)
  const response = await fetcher("/auth/privy/session", {
    method: "POST",
    credentials: "same-origin",
    headers: {authorization: `Bearer ${accessToken}`, "x-csrf-token": csrf},
  })
  if (!response.ok) throw new Error("Sign in could not be completed.")
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
  const loginCallbacks = React.useMemo(
    () => createPrivyLoginCallbacks(getAccessToken, completeLogin),
    [completeLogin, getAccessToken],
  )
  const {login} = useLogin(loginCallbacks)
  const loginGate = React.useMemo(() => createReadyLoginGate(login), [login])
  const walletSyncGeneration = React.useRef(0)

  React.useEffect(() => loginGate.setReady(ready), [loginGate, ready])

  React.useEffect(() => {
    if (!ready || !authenticated) return

    void getAccessToken().then(accessToken => {
      if (accessToken) void completeLogin(accessToken).catch(() => undefined)
    })
  }, [authenticated, completeLogin, getAccessToken, ready])

  const synchronizeWallets = React.useCallback(async () => {
    const generation = ++walletSyncGeneration.current
    if (!ready || !authenticated || wallets.length === 0) {
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
  }, [authenticated, ready, wallets])

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
        clearSession: clearLocalSession,
        providerLogout: logout,
        reload: () => window.location.reload(),
        synchronizeWallets,
      }),
    [loginGate, logout, synchronizeWallets],
  )

  React.useEffect(
    () => publishRequestHandler(requestHandler, ready),
    [publishRequestHandler, ready, requestHandler],
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
    let resolved = false
    const handle: PrivyBridgeHandle = {
      request(request) {
        return currentRequestHandler
          ? currentRequestHandler(request)
          : Promise.reject(new Error("Privy bridge is not ready"))
      },
    }
    const publishRequestHandler: AccountBridgeProps["publishRequestHandler"] = (
      requestHandler,
      ready,
    ) => {
      currentRequestHandler = requestHandler
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
