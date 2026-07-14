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

import {
  replaceConnectedEthereumWallets,
  type EthereumProvider,
} from "./wallet_actions/connected_wallet"

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

function AccountBridge() {
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

  React.useEffect(() => loginGate.setReady(ready), [loginGate, ready])

  React.useEffect(() => {
    if (!ready || !authenticated) return

    void getAccessToken().then(accessToken => {
      if (accessToken) void completeLogin(accessToken).catch(() => undefined)
    })
  }, [authenticated, completeLogin, getAccessToken, ready])

  React.useEffect(() => {
    if (!authenticated) {
      replaceConnectedEthereumWallets([])
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
    }
  }, [authenticated])

  React.useEffect(() => {
    let cancelled = false
    if (!ready || wallets.length === 0) {
      replaceConnectedEthereumWallets([])
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
      return
    }

    void Promise.all(
      wallets.map(async wallet => [wallet.address.toLowerCase(), (await wallet.getEthereumProvider()) as EthereumProvider] as const),
    ).then(entries => {
      if (cancelled) return
      replaceConnectedEthereumWallets(entries)
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
    })

    return () => {
      cancelled = true
    }
  }, [ready, wallets])

  React.useEffect(() => {
    const control = document.querySelector<HTMLElement>("#account-control")
    if (!control) return

    const onClick = async (event: Event) => {
      const target = event.target instanceof Element ? event.target : null

      if (target?.closest("[data-account-target='sign-in']")) {
        loginGate.requestLogin()
        return
      }

      if (target?.closest("[data-account-target='sign-out']")) {
        await clearLocalSession()
        try {
          await logout()
        } finally {
          window.location.reload()
        }
      }
    }

    control.addEventListener("click", onClick)
    return () => control.removeEventListener("click", onClick)
  }, [loginGate, logout])

  return null
}

export function startPrivyBridge(): void {
  const appId = document.querySelector<HTMLMetaElement>("meta[name='privy-app-id']")?.content
  if (!appId) return
  const host = document.createElement("div")
  host.hidden = true
  document.body.append(host)
  createRoot(host).render(
    <PrivyProvider appId={appId} config={{loginMethods: ["wallet"]}}>
      <AccountBridge />
    </PrivyProvider>,
  )
}
