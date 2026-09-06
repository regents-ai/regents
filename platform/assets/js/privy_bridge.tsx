import {createClaimsClient, type ClaimsAction} from "./owned_claims"
import {createProfileClient, type ProfileAction} from "../vendor/regent_identity/profile_client.mjs"
import {createXLinkIntent} from "../vendor/regent_identity/x_link_intent.mjs"
import {
  PrivyProvider,
  type ConnectedWallet,
  type PrivyEvents,
  getIdentityToken,
  useActiveWallet,
  useConnectWallet,
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
  AccountAuthFailure,
  acrossCookieRotation,
  announceCsrfRotation,
  browserSessionMutations,
  clearLocalSession,
  csrfToken,
  recoverOnce,
  reportSignInFailure,
  reloadDocumentOnce,
  sessionLifecycleError,
  showAccountAuthFailure,
  type AccountRequest,
  type IdentityRequest,
  type PrivyBridgeHandle,
  type PrivyBridgeStartupOptions,
  type SessionMutationCoordinator,
  type SignInFailureDiagnostic,
  type SignInFailureKind,
} from "./auth_lazy"
import {
  activeEthereumWallet,
  forgetWalletDisconnected,
  replaceActiveEthereumWallet,
  replaceConnectedEthereumWallets,
  walletDisconnected,
  type EthereumProvider,
} from "./wallet_actions/connected_wallet"

type AccountRequestHandlerOptions = {
  connectWallet: () => Promise<void>
  signIn: () => Promise<void>
  providerLogout: () => Promise<void>
  synchronizeWallets: () => Promise<void>
}

export function createAccountRequestHandler({
  connectWallet,
  signIn,
  providerLogout,
  synchronizeWallets,
}: AccountRequestHandlerOptions): (request: AccountRequest) => Promise<void> {
  return async request => {
    // Asking for a wallet is not getting one: both of these only open Privy's
    // own window, and they answer as soon as it is open. What ends the
    // disconnected state is the visitor coming back with a wallet, which Privy
    // reports on its own callbacks, so nothing about the Disconnect changes
    // here.
    if (request === "connect-wallet") {
      await connectWallet()
      return
    }

    if (request === "sign-in") {
      await signIn()
      return
    }

    if (request === "sync") {
      await synchronizeWallets()
      return
    }

    await providerLogout()
  }
}

// Both refusals carry the same message. This type is never exported, so only a
// sign in inside this module can tell the one refusal the server marked as
// recoverable apart from every other one, which stays generic and final.
class ServerReportedSessionError extends Error {
  constructor() {
    super("Sign in could not be completed.")
  }
}

class StaleProviderSessionError extends ServerReportedSessionError {
  constructor() {
    super()
  }
}

function refusal(response: Response): Error {
  if (response.status !== 401) return new Error("Sign in could not be completed.")

  return response.headers.get("x-ash-provider-relogin") === "allowed"
    ? new StaleProviderSessionError()
    : new ServerReportedSessionError()
}

type SignInRequestOptions = {
  authenticated: () => boolean
  completeLogin: () => Promise<void>
  providerLogout: () => Promise<void>
  openLogin: () => void
  loginOpen: {current: boolean}
  recoveryAvailable: {current: boolean}
}

// The recovery cap is spent before the logout is awaited, and the logout
// completes before anything may be sent again, so the pair the server just
// refused can never be offered a second time and a later refusal simply stops.
export function createSignInRequest({
  authenticated,
  completeLogin,
  providerLogout,
  openLogin,
  loginOpen,
  recoveryAvailable,
}: SignInRequestOptions): {signIn: () => Promise<void>; recovering: () => boolean} {
  let recovering = false

  const openLoginOnce = () => {
    if (loginOpen.current) return
    loginOpen.current = true
    openLogin()
  }

  return {
    recovering: () => recovering,
    async signIn() {
      if (!authenticated()) return openLoginOnce()

      try {
        await completeLogin()
      } catch (refused) {
        if (!(refused instanceof StaleProviderSessionError) || !recoveryAvailable.current) {
          throw new AccountAuthFailure(
            "session",
            "session_exchange",
            refused instanceof ServerReportedSessionError,
          )
        }

        recoveryAvailable.current = false
        recovering = true
        try {
          await providerLogout()
        } catch {
          throw new AccountAuthFailure("session", "session_exchange")
        } finally {
          recovering = false
        }
        openLoginOnce()
      }
    },
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

type SignOutOnlyBridgeOptions = {
  ordinaryRequest: (request: AccountRequest) => Promise<void>
  ordinaryIdentity: (request: IdentityRequest) => Promise<void>
  onTerminal?: () => void
}

export function createSignOutOnlyBridgeState({
  ordinaryRequest,
  ordinaryIdentity,
  onTerminal = () => undefined,
}: SignOutOnlyBridgeOptions) {
  let state: "preterminal" | "terminal" = "preterminal"
  let providerSignOutAttempt: Promise<void> | null = null
  let explicitRequestTail = Promise.resolve()

  const finish = () => {
    if (state === "terminal") return
    state = "terminal"
    onTerminal()
  }

  const afterProviderSignOut = <T,>(request: () => Promise<T>): Promise<T> => {
    const providerSettled = providerSignOutAttempt?.then(
      () => undefined,
      () => undefined,
    ) ?? Promise.resolve()
    const attempt = explicitRequestTail.then(() => providerSettled).then(request)
    explicitRequestTail = attempt.then(
      () => undefined,
      () => undefined,
    )
    return attempt
  }

  return {
    request(request: AccountRequest): Promise<void> {
      if (state === "terminal") {
        if (request === "sign-out") return Promise.resolve()
        if (request === "sync") {
          return Promise.reject(new Error("Automatic reconciliation is disabled."))
        }
        return afterProviderSignOut(() => ordinaryRequest(request))
      }
      if (request !== "sign-out") {
        return Promise.reject(new Error("Provider sign out is still in progress."))
      }
      if (providerSignOutAttempt) return providerSignOutAttempt

      const attempt = ordinaryRequest("sign-out")
      providerSignOutAttempt = attempt
      void attempt.then(finish, finish)
      return attempt
    },
    identity(request: IdentityRequest): Promise<void> {
      return state === "terminal"
        ? afterProviderSignOut(() => ordinaryIdentity(request))
        : Promise.reject(new Error("Provider sign out is still in progress."))
    },
    finish,
  }
}

export {clearLocalSession, csrfToken}

// Privy's two tokens have two different jobs: the access token proves this
// browser's Privy session and the identity token carries the signed accounts
// that session is entitled to. Regent needs both, so they travel together.
export type PrivyTokenPair = {accessToken: string; identityToken: string}

type PrivyTokenSources = {
  getIdentityToken: () => Promise<string | null>
  getAccessToken: () => Promise<string | null>
}

// The evidence is asked for first and the session proof second, so the proof is
// never older than the evidence it is offered with. A half pair is never sent:
// if either read fails or comes back empty, nothing is requested at all and any
// local session this browser already holds is left exactly as it is.
export function createPrivyTokenPairSource({
  getIdentityToken: identity,
  getAccessToken: access,
}: PrivyTokenSources): () => Promise<PrivyTokenPair> {
  return async () => {
    const identityToken = await identity()
    const accessToken = await access()

    if (!identityToken?.trim() || !accessToken?.trim()) {
      throw new Error("Sign in could not be completed.")
    }

    return {accessToken, identityToken}
  }
}

export async function createLocalSession(
  tokens: PrivyTokenPair,
  fetcher: typeof fetch = fetch,
  sessionMutations: SessionMutationCoordinator = browserSessionMutations,
): Promise<{
  sessionChanged: boolean
  identityError?: "already-connected"
}> {
  // The barrier spans the whole establishment, including the recovery attempt
  // that follows a dropped lineage. Only the outcomes that actually write a
  // session leave this tab holding a token it has not confirmed, so an attempt
  // refused before one of those lands renews nothing and leaves reconnects
  // available.
  return sessionMutations.establish((signal, commit) =>
    acrossCookieRotation(renewed =>
      recoverOnce(() => establishLocalSession(tokens, fetcher, signal, commit, renewed)),
    ),
  )
}

async function establishLocalSession(
  {accessToken, identityToken}: PrivyTokenPair,
  fetcher: typeof fetch,
  signal: AbortSignal,
  commit: () => void,
  renewed: () => void,
): Promise<{sessionChanged: boolean; identityError?: "already-connected"}> {
  const csrf = await csrfToken(fetcher, signal, renewed)
  if (signal.aborted) throw signal.reason
  // From here the response may renew the cookie, so it is never abandoned: an
  // abandoned renewal would leave this tab holding a retired token.
  commit()
  // Each token travels in its own header and never in the URL or the body.
  const response = await fetcher("/auth/privy/session", {
    method: "POST",
    credentials: "same-origin",
    headers: {
      authorization: `Bearer ${accessToken}`,
      "privy-id-token": identityToken,
      "x-csrf-token": csrf,
    },
  })
  const lifecycle = await sessionLifecycleError(response).catch(unreadable => {
    // An account switch and a revoked lineage both drop the cookie at header
    // time and both answer 409, so a conflict this tab cannot read counts as
    // the drop it has not adopted.
    renewed()
    throw unreadable
  })
  // The exact sign-in outcomes that leave a different cookie in this browser: a
  // bind or refresh rotates it, and a refused bearer, an account switch or a
  // revoked lineage drop it. Only a superseded claim writes no session, and only
  // its own parsed body proves that.
  const wroteSession =
    response.status === 409
      ? lifecycle?.lifecycle !== "session_superseded"
      : response.ok || response.status === 401
  if (wroteSession) renewed()
  if (lifecycle) throw lifecycle
  if (!response.ok) throw refusal(response)
  const sessionChanged = response.headers.get("x-ash-session-changed")
  if (sessionChanged !== "true" && sessionChanged !== "false") {
    throw new Error("Sign in could not be completed.")
  }
  const identityError = response.headers.get("x-ash-identity-error")
  if (identityError && identityError !== "already-connected") {
    throw new Error("Sign in could not be completed.")
  }
  const verifiedIdentityError = identityError === "already-connected" ? identityError : undefined
  // The renewed session rotated its CSRF state: this tab adopts the new token
  // and tells the other tabs sharing the cookie to adopt it too.
  await csrfToken(fetcher)
  announceCsrfRotation()
  return {
    sessionChanged: sessionChanged === "true",
    ...(verifiedIdentityError ? {identityError: verifiedIdentityError} : {}),
  }
}

// Privy allocates a new ConnectedWallet object for the same wallet whenever its
// chain, link state or connection is refreshed, and finds its selection by
// address inside that fresh array, so object identity says nothing about whether
// the customer changed wallets. Address and wallet app do: two apps holding one
// address are still two wallets, and Privy names an injected app it does not
// recognise "unknown", so a new object from such an app, or one with no app
// identity at all, cannot be told from another app's and is treated as a change.
// Whether the same provider stands behind a recognised object is only known once
// it resolves, and is decided at publication.
function sameConnectedWallet(
  previous: ConnectedWallet | null,
  next: ConnectedWallet | null,
): boolean {
  if (!previous || !next) return previous === next
  if (previous === next) return true
  const app = previous.walletClientType
  if (!app || app === "unknown" || !previous.connectorType) return false
  return (
    previous.address.toLowerCase() === next.address.toLowerCase() &&
    app === next.walletClientType &&
    previous.connectorType === next.connectorType
  )
}

// The one account the same wallet app now reports in place of the account the
// customer had selected there. Anything else is not a switch: the selected
// account still listed, that app gone entirely, several of its accounts to
// choose between, or an account from a different app.
export function switchedAccountOf(
  previous: ConnectedWallet | null,
  wallets: readonly ConnectedWallet[],
): ConnectedWallet | null {
  // Privy names an injected provider it does not recognise "unknown", so two
  // such apps are indistinguishable and neither may stand in for the other.
  if (!previous || previous.walletClientType === "unknown") return null
  const sameApp = wallets.filter(
    wallet =>
      wallet.type === "ethereum" &&
      wallet.walletClientType === previous.walletClientType &&
      wallet.connectorType === previous.connectorType,
  )
  const [candidate] = sameApp
  return sameApp.length === 1 && candidate.address.toLowerCase() !== previous.address.toLowerCase()
    ? candidate
    : null
}

type ProviderSessionReconcilerOptions = {
  clearSession: () => Promise<void>
  providerAuthenticated: () => boolean
  reload: () => void
  signedIn: () => boolean
}

// Startup reconciliation only reads the provider. Remaining signed in is not a
// session event: this can end a local session the provider no longer supports,
// but it can never establish or refresh one, so an ordinary signed-in load
// advances no generation, renews no cookie and rotates no CSRF state.
export function createProviderSessionReconciler({
  clearSession,
  providerAuthenticated,
  reload,
  signedIn,
}: ProviderSessionReconcilerOptions): () => Promise<boolean> {
  return async () => {
    if (providerAuthenticated()) return true
    // Only a page that still shows its signed-in account control has a session
    // to end, and only this reading of it counts: the page may have been
    // replaced while the provider was being sampled, and an anonymous page waiting
    // for its first sign in must be left exactly as it is.
    if (!signedIn()) return true

    await clearSession()
    reload()
    return false
  }
}

const showsSignOutControl = () =>
  document.querySelector("#account-control [data-account-target='sign-out']") !== null

type PrivySessionCompletionOptions = {
  acquireTokens: () => Promise<PrivyTokenPair>
  fetcher?: typeof fetch
  localSessionNeeded: () => boolean
  reload: () => void
}

// The pair is acquired inside the attempt, so every entry point — a granted
// token, an explicit sign in, a same-account refresh — asks Privy for one
// complete, current pair and sends nothing when it cannot get one.
export function createPrivySessionCompletion({
  acquireTokens,
  fetcher = fetch,
  localSessionNeeded,
  reload,
}: PrivySessionCompletionOptions): () => Promise<void> {
  let inFlight: Promise<void> | null = null

  return () => {
    if (!localSessionNeeded()) return Promise.resolve()
    if (inFlight) return inFlight

    const attempt = (async () => {
      await createLocalSession(await acquireTokens(), fetcher)
      reload()
    })()

    inFlight = attempt
    void attempt.catch(() => {
      if (inFlight === attempt) inFlight = null
    })

    return attempt
  }
}

export function createPrivyTokenCallbacks(completeLogin: () => Promise<void>) {
  return {
    onAccessTokenGranted: () => completeLogin().catch(() => undefined),
    onAccessTokenRemoved: () => undefined,
  } satisfies PrivyEvents["accessToken"]
}

type PrivyLoginCallbackOptions = {
  allowAutomatic?: boolean
  completeLogin: () => Promise<void>
  loginOpen: {current: boolean}
  showFailure: (failure: SignInFailureKind) => void
  reportFailure?: (failure: SignInFailureDiagnostic) => void
}

const privyLoginFailureDiagnostics: Partial<Record<string, SignInFailureDiagnostic>> = {
  exited_auth_flow: "flow_closed",
  client_request_timeout: "request_timeout",
  invalid_message: "invalid_message",
  unable_to_sign: "unable_to_sign",
}

export function privyLoginFailureDiagnostic(error: unknown): SignInFailureDiagnostic {
  return privyLoginFailureDiagnostics[typeof error === "string" ? error : ""] ?? "provider_error"
}

// Privy runs this for its own provider bootstrap too, for a modal this page
// never opened, and that entry shares the one in-flight completion with a
// deliberate click. Only a modal this page opened may speak for it, so a
// bootstrap refusal stays silent while the click recovers behind it, and a
// completion this page asked for — including one Privy runs synchronously for
// an already-authenticated customer, after the click that opened login has
// settled — says so rather than rejecting into nothing. Both outcomes close
// the modal, so both release the guard for the next click.
export function createPrivyLoginCallbacks({
  allowAutomatic = true,
  completeLogin,
  loginOpen,
  showFailure,
  reportFailure = reportSignInFailure,
}: PrivyLoginCallbackOptions): PrivyEvents["login"] {
  return {
    onComplete: () => {
      const opened = loginOpen.current
      loginOpen.current = false
      if (!opened && !allowAutomatic) return
      // The visitor signed in, which is one of the two ways they come back with
      // a wallet. This runs before the session completion reloads the document,
      // so the page that replaces this one reads a cleared note on its first
      // wallet sync.
      forgetWalletDisconnected()
      void completeLogin().catch(error => {
        if (!opened) return
        if (!(error instanceof ServerReportedSessionError)) {
          reportFailure("session_exchange")
        }
        showFailure("session")
      })
    },
    onError: error => {
      const opened = loginOpen.current
      loginOpen.current = false
      if (!opened) return
      const diagnostic = privyLoginFailureDiagnostic(error)
      reportFailure(diagnostic)
      showFailure(diagnostic === "flow_closed" ? "closed" : "provider")
    },
  } satisfies PrivyEvents["login"]
}

type AccountBridgeProps = {
  mode: "ordinary" | "sign-out-only" | "profile-only"
  providerState?: PrivyBridgeProviderState
  publishRequestHandler: (
    requestHandler: PrivyBridgeHandle["request"],
    identityHandler: NonNullable<PrivyBridgeHandle["identity"]>,
    finishSignOutOnly: () => void,
    ready: boolean,
    profileHandler: ProfileAction,
    claimsHandler: ClaimsAction,
  ) => void
}

export type PrivyBridgeProviderState = {
  userId?: string
  appId: string
  authenticated: boolean
  getAccessToken: () => Promise<string | null>
  getIdentityToken?: () => Promise<string | null>
  logout: () => Promise<void>
  ready: boolean
  walletsReady: ReturnType<typeof useWallets>["ready"]
  wallets: ReturnType<typeof useWallets>["wallets"]
  activeWallet?: ReturnType<typeof useActiveWallet>["wallet"]
  connectActiveWallet?: ReturnType<typeof useActiveWallet>["connect"]
  setActiveWallet?: ReturnType<typeof useActiveWallet>["setActiveWallet"]
  connectWallet?: ReturnType<typeof useConnectWallet>["connectWallet"]
}

function AccountBridge({mode, providerState, publishRequestHandler}: AccountBridgeProps) {
  const privy = usePrivy()
  const providerWallets = useWallets()
  const providerActiveWallet = useActiveWallet()
  // The other way a visitor comes back with a wallet: they finished Privy's
  // connect flow. Abandoning that window never reaches here, so the Disconnect
  // stands until a wallet is actually connected again.
  const providerWalletConnector = useConnectWallet({onSuccess: forgetWalletDisconnected})
  const authenticated = providerState?.authenticated ?? privy.authenticated
  const logout = providerState?.logout ?? privy.logout
  const ready = providerState?.ready ?? privy.ready
  const walletsReady = providerState?.walletsReady ?? providerWallets.ready
  const wallets = providerState?.wallets ?? providerWallets.wallets
  const activeWallet = providerState?.activeWallet ?? providerActiveWallet.wallet
  const connectActiveWallet = providerState?.connectActiveWallet ?? providerActiveWallet.connect
  const setActiveWallet = providerState?.setActiveWallet ?? providerActiveWallet.setActiveWallet
  const connectWallet = providerState?.connectWallet ?? providerWalletConnector.connectWallet
  const signOutOnly = mode === "sign-out-only"
  const signOutOnlyState = React.useRef<"preterminal" | "terminal">(
    signOutOnly ? "preterminal" : "terminal",
  )
  // Acquisition depends on the provider hooks below, while the one in-flight
  // attempt these callbacks share must survive every rerender, so the stable
  // completion reads the latest pair source rather than closing over one.
  const acquireTokensRef = React.useRef<() => Promise<PrivyTokenPair>>(() =>
    Promise.reject(new Error("Sign in could not be completed.")),
  )
  const completeExplicitLogin = React.useMemo(
    () =>
      createPrivySessionCompletion({
        acquireTokens: () => acquireTokensRef.current(),
        localSessionNeeded: () =>
          (!signOutOnly || signOutOnlyState.current === "terminal") &&
          document.querySelector("#account-control [data-account-target='sign-in']") !== null,
        reload: () => window.location.reload(),
      }),
    [signOutOnly],
  )
  const loginOpen = React.useRef(false)
  const recoveryAvailable = React.useRef(true)
  const loginCallbacks = React.useMemo(
    () =>
      createPrivyLoginCallbacks({
        completeLogin: completeExplicitLogin,
        allowAutomatic: mode !== "profile-only",
        loginOpen,
        showFailure: failure => showAccountAuthFailure("sign-in", document, failure),
      }),
    [completeExplicitLogin, mode],
  )
  const {login} = useLogin(loginCallbacks)
  // The published handler outlives every render, so the click it answers reads
  // the provider of the latest committed render — never one React started and
  // discarded — which is why this is written after the commit and before the
  // effect that publishes the handler.
  const subject = providerState?.userId ?? privy.user?.id ?? null
  const provider = React.useRef({authenticated, login, logout, ready, subject})
  const profileGeneration = React.useRef(0)
  React.useEffect(() => {
    const changed = provider.current.authenticated !== authenticated || provider.current.subject !== subject
    provider.current = {authenticated, login, logout, ready, subject}
    if (changed) {
      profileGeneration.current += 1
      window.dispatchEvent(new Event("regent:profile-identity"))
    }
  }, [authenticated, login, logout, ready, subject])
  const signInRequest = React.useMemo(
    () =>
      createSignInRequest({
        authenticated: () => provider.current.authenticated,
        completeLogin: completeExplicitLogin,
        providerLogout: () => provider.current.logout(),
        openLogin: () => provider.current.login(),
        loginOpen,
        recoveryAvailable,
      }),
    [completeExplicitLogin],
  )
  // Adoption only ever asks the server, and it stands aside entirely while an
  // explicit recovery still holds the pair the server refused.
  const completeAutomaticLogin = React.useCallback(
    () =>
      signOutOnly || mode === "profile-only" || signInRequest.recovering() ? Promise.resolve() : completeExplicitLogin(),
    [completeExplicitLogin, signInRequest, signOutOnly, mode],
  )
  const tokenCallbacks = React.useMemo(
    () => createPrivyTokenCallbacks(completeAutomaticLogin),
    [completeAutomaticLogin],
  )
  const providerToken = useToken(tokenCallbacks)
  const getAccessToken = providerState?.getAccessToken ?? providerToken.getAccessToken
  const acquireTokens = React.useMemo(
    () =>
      createPrivyTokenPairSource({
        getIdentityToken: providerState?.getIdentityToken ?? getIdentityToken,
        getAccessToken,
      }),
    [getAccessToken, providerState?.getIdentityToken],
  )
  acquireTokensRef.current = acquireTokens
  const acquireProfileProof = React.useCallback(async ({signal}: {signal: AbortSignal}, expectedSubject?: string) => {
    while (!provider.current.ready || (expectedSubject && provider.current.subject !== expectedSubject)) {
      signal.throwIfAborted()
      await new Promise(resolve => setTimeout(resolve, 25))
    }
    const state = provider.current
    if (!state.authenticated || !state.subject || (expectedSubject && expectedSubject !== state.subject) ||
        (signOutOnly && signOutOnlyState.current !== "terminal")) return null
    const generation = profileGeneration.current
    const tokens = await acquireTokensRef.current()
    return {...tokens, subject: state.subject, isCurrent: () =>
      provider.current.authenticated && provider.current.subject === state.subject && profileGeneration.current === generation}
  }, [signOutOnly])
  const profileFor = React.useCallback((expectedSubject?: string) => createProfileClient({
    acquireProof: options => acquireProfileProof(options, expectedSubject),
  }), [acquireProfileProof])
  const profileHandler = React.useMemo(() => profileFor(), [profileFor])
  const claimsHandler = React.useMemo(() => createClaimsClient({acquireProof: acquireProfileProof}), [acquireProfileProof])
  const profileIntent = React.useCallback(() => {
    const appId = providerState?.appId ?? document.querySelector<HTMLMetaElement>("meta[name='privy-app-id']")?.content ?? ""
    let storage: Storage | null = null
    try { storage = window.sessionStorage } catch {}
    return createXLinkIntent(storage, appId)
  }, [providerState?.appId])
  const profileLinkNonce = React.useRef<string | null>(null)
  const notifyProfileLink = React.useCallback((ok: boolean) => {
    window.dispatchEvent(new CustomEvent("regent:profile-link", {detail: {ok}}))
  }, [])
  const notifyIdentityState = React.useCallback((error: string | null) => {
    window.dispatchEvent(
      new CustomEvent("ash:identity-state", {detail: {error}}),
    )
  }, [])
  const refreshIdentitySession = React.useCallback(async () => {
    const result = await createLocalSession(await acquireTokens())
    notifyIdentityState(result.identityError ?? null)
  }, [acquireTokens, notifyIdentityState])
  const linkCallbacks = React.useMemo(
    () => ({
      onSuccess: (payload: Parameters<NonNullable<PrivyEvents["linkAccount"]["onSuccess"]>>[0]) => {
        const expected = profileIntent().claim(payload)
        if (expected) {
          void profileFor(expected)("sync").then(result => notifyProfileLink(result.ok))
        }
        void refreshIdentitySession().catch(() => notifyIdentityState("failed"))
      },
      onError: () => {
        profileIntent().cancel(profileLinkNonce.current)
        notifyProfileLink(false)
        notifyIdentityState("failed")
      },
    }),
    [notifyIdentityState, refreshIdentitySession, profileIntent, profileFor, notifyProfileLink],
  )
  const {linkTwitter, linkGithub, linkFarcaster} = useLinkAccount(linkCallbacks)
  const {unlink: unlinkOAuth} = useUnlinkOAuth()
  const {unlink: unlinkFarcasterAccount} = useUnlinkFarcaster()
  const walletSyncGeneration = React.useRef(0)
  const selectedWalletRef = React.useRef<ConnectedWallet | null>(null)
  const reconcileProviderSession = React.useMemo(
    () =>
      createProviderSessionReconciler({
        clearSession: () => browserSessionMutations.signOut(clearLocalSession),
        providerAuthenticated: () => authenticated,
        reload: () => reloadDocumentOnce(document, () => window.location.reload()),
        signedIn: showsSignOutControl,
      }),
    [authenticated],
  )

  React.useEffect(() => {
    if (signOutOnly || !ready || !authenticated) return

    void completeAutomaticLogin().catch(() => undefined)
  }, [authenticated, completeAutomaticLogin, ready, signOutOnly])

  // The active selection is published alongside the connected set and depends on
  // it, so a selection change with an unchanged wallets array still runs this and
  // still announces `ash:wallet-state`.
  const synchronizeWallets = React.useCallback(async () => {
    const generation = ++walletSyncGeneration.current

    // Disconnect is the visitor's own choice and outlives the document it was
    // made in. Until they connect a wallet or sign in again, nothing the wallet
    // app still reports to Privy is this page's wallet.
    if (walletDisconnected()) {
      selectedWalletRef.current = null
      replaceConnectedEthereumWallets([])
      replaceActiveEthereumWallet(null)
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
      return
    }

    const selectedWallet =
      activeWallet?.type === "ethereum" &&
      wallets.some(wallet => wallet.address.toLowerCase() === activeWallet.address.toLowerCase())
        ? activeWallet
        : null
    const switchedAccount = selectedWallet ? null : switchedAccountOf(selectedWalletRef.current, wallets)

    // The wallet the customer just left stops being Stake's wallet here, before
    // any of the work below can await, so nothing can be prepared or sent for it
    // while the newly selected provider is still resolving.
    if (activeEthereumWallet() && !sameConnectedWallet(selectedWalletRef.current, selectedWallet)) {
      replaceActiveEthereumWallet(null)
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
    }
    selectedWalletRef.current = selectedWallet

    // An account switched inside the wallet app the customer was already using
    // is their own choice, so Privy's selection follows it. This run ends with
    // no wallet; the run Privy's new selection starts publishes the account.
    if (switchedAccount) {
      setActiveWallet(switchedAccount)
      return
    }

    // A sign-out-only bridge has just ended the session on purpose, so there is
    // nothing to reconcile; reconciling would end it a second time and reload.
    const reconciled = ready && (signOutOnly || (await reconcileProviderSession()))
    if (!reconciled || !walletsReady) {
      if (walletSyncGeneration.current !== generation) return
      replaceConnectedEthereumWallets([])
      replaceActiveEthereumWallet(null)
      window.dispatchEvent(new CustomEvent("ash:wallet-state"))
      return
    }

    // Each connected wallet's provider is resolved once, and the selection is
    // taken from those resolved entries. A wallet whose provider does not
    // resolve is not a wallet here, so a failed selection leaves Stake with no
    // active wallet rather than with the previous one.
    const resolved = await Promise.allSettled(
      wallets.map(async wallet => ({
        address: wallet.address.toLowerCase(),
        provider: (await wallet.getEthereumProvider()) as EthereumProvider,
        // Privy's own way of letting go of this wallet, carried beside the
        // provider so Disconnect can release both without the bridge.
        disconnect: () => wallet.disconnect(),
      })),
    )
    if (walletSyncGeneration.current !== generation) return

    const entries = resolved.flatMap(result => (result.status === "fulfilled" ? [result.value] : []))
    const selectedIndex = selectedWallet ? wallets.indexOf(selectedWallet) : -1
    const selectedResult = selectedIndex >= 0 ? resolved[selectedIndex] : null
    let selectedProvider =
      selectedResult?.status === "fulfilled" ? selectedResult.value.provider : null
    if (selectedWallet && selectedIndex < 0) {
      try {
        selectedProvider = (await selectedWallet.getEthereumProvider()) as EthereumProvider
      } catch {
        selectedProvider = null
      }
      if (walletSyncGeneration.current !== generation) return
    }
    // Everything above was awaited, so Disconnect may have landed while this
    // sync was in flight. The generation counter only knows about newer syncs,
    // which is why the visitor's own choice is read again here, last.
    if (walletDisconnected()) return

    replaceConnectedEthereumWallets(
      entries.map(entry => [entry.address, {provider: entry.provider, disconnect: entry.disconnect}]),
    )
    replaceActiveEthereumWallet(
      selectedWallet && selectedProvider
        ? {address: selectedWallet.address, provider: selectedProvider}
        : null,
    )
    window.dispatchEvent(new CustomEvent("ash:wallet-state"))
  }, [
    activeWallet,
    ready,
    reconcileProviderSession,
    setActiveWallet,
    signOutOnly,
    wallets,
    walletsReady,
  ])

  // A sign-out-only bridge publishes nothing while the provider sign out is
  // still settling. From the moment it settles it publishes exactly as an
  // ordinary bridge does: the wallets Privy still holds, and every wallet the
  // customer connects afterwards on this page.
  const synchronizeWalletsRef = React.useRef(synchronizeWallets)
  synchronizeWalletsRef.current = synchronizeWallets

  React.useEffect(() => {
    if (signOutOnly && signOutOnlyState.current !== "terminal") return
    void synchronizeWallets()
    return () => {
      walletSyncGeneration.current += 1
    }
  }, [signOutOnly, synchronizeWallets])

  const connectSelectedWallet = React.useCallback(async () => {
    if (wallets.length === 0) {
      // Privy's window says whether the visitor finished, on the connector's own
      // success callback above, so there is nothing to read from this answer.
      await Promise.resolve(
        connectWallet({
          walletChainType: "ethereum-only",
          description: "Connect a wallet to stake or redeem on Base.",
        }),
      )
      return
    }

    // Privy already holds this wallet, so connecting it answers with the wallet
    // itself. An answer carrying one is the visitor back with a wallet.
    const {wallet} = await connectActiveWallet()
    if (wallet) forgetWalletDisconnected()
  }, [connectActiveWallet, connectWallet, wallets.length])

  const markSignOutTerminal = React.useCallback(() => {
    signOutOnlyState.current = "terminal"
    walletSyncGeneration.current += 1
    void synchronizeWalletsRef.current()
  }, [])

  const ordinaryRequestHandler = React.useMemo(
    () =>
      createAccountRequestHandler({
        connectWallet: connectSelectedWallet,
        signIn: signInRequest.signIn,
        providerLogout: () => provider.current.logout(),
        synchronizeWallets,
      }),
    [connectSelectedWallet, signInRequest, synchronizeWallets],
  )

  const ordinaryIdentityHandler = React.useMemo(
    () =>
      createIdentityRequestHandler({
        linkX: () => {
          const currentSubject = provider.current.subject
          if (!currentSubject || !provider.current.authenticated) throw new Error("authentication_required")
          const nonce = profileIntent().begin(currentSubject)
          profileLinkNonce.current = nonce
          Promise.resolve(linkTwitter()).catch(() => {
            profileIntent().cancel(nonce)
            notifyProfileLink(false)
          })
        },
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
      profileIntent,
      notifyProfileLink,
      refreshIdentitySession,
      unlinkFarcasterAccount,
      unlinkOAuth,
    ],
  )

  const ordinaryRequestHandlerRef = React.useRef(ordinaryRequestHandler)
  const ordinaryIdentityHandlerRef = React.useRef(ordinaryIdentityHandler)
  ordinaryRequestHandlerRef.current = ordinaryRequestHandler
  ordinaryIdentityHandlerRef.current = ordinaryIdentityHandler

  const signOutOnlyBridge = React.useMemo(
    () =>
      createSignOutOnlyBridgeState({
        ordinaryRequest: request => ordinaryRequestHandlerRef.current(request),
        ordinaryIdentity: request => ordinaryIdentityHandlerRef.current(request),
        onTerminal: markSignOutTerminal,
      }),
    [markSignOutTerminal],
  )
  const requestHandler = signOutOnly
    ? signOutOnlyBridge.request
    : ordinaryRequestHandler
  const identityHandler = signOutOnly
    ? signOutOnlyBridge.identity
    : ordinaryIdentityHandler
  const finishSignOutOnly = signOutOnlyBridge.finish

  React.useEffect(
    () => publishRequestHandler(requestHandler, identityHandler, finishSignOutOnly, ready, profileHandler, claimsHandler),
    [finishSignOutOnly, identityHandler, publishRequestHandler, ready, requestHandler, profileHandler, claimsHandler],
  )

  return null
}

export function startPrivyBridge(
  {mode = "ordinary"}: PrivyBridgeStartupOptions = {},
  providerState?: PrivyBridgeProviderState,
): Promise<PrivyBridgeHandle> {
  const appId =
    providerState?.appId ??
    document.querySelector<HTMLMetaElement>("meta[name='privy-app-id']")?.content
  if (!appId) return Promise.reject(new Error("Privy app is unavailable"))
  const host = document.createElement("div")
  host.hidden = true
  document.body.append(host)

  return new Promise(resolve => {
    let currentRequestHandler: PrivyBridgeHandle["request"] | null = null
    let currentIdentityHandler: PrivyBridgeHandle["identity"] | null = null
    let currentFinishSignOutOnly: (() => void) | null = null
    let currentProfileHandler: ProfileAction | null = null
    let currentClaimsHandler: ClaimsAction | null = null
    let resolved = false
    const handle: PrivyBridgeHandle = {
      claims(...args) {
        return currentClaimsHandler ? currentClaimsHandler(...args) : Promise.reject(new Error("Claims are unavailable"))
      },
      profile(...args) {
        return currentProfileHandler ? currentProfileHandler(...args) : Promise.reject(new Error("Profile is unavailable"))
      },
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
      finishSignOutOnly() {
        currentFinishSignOutOnly?.()
      },
    }
    const publishRequestHandler: AccountBridgeProps["publishRequestHandler"] = (
      requestHandler,
      identityHandler,
      finishSignOutOnly,
      ready,
      profileHandler,
      claimsHandler,
    ) => {
      currentClaimsHandler = claimsHandler
      currentProfileHandler = profileHandler
      currentRequestHandler = requestHandler
      currentIdentityHandler = identityHandler
      currentFinishSignOutOnly = finishSignOutOnly
      if (!ready || resolved) return
      resolved = true
      resolve(handle)
    }

    createRoot(host).render(
      <PrivyProvider appId={appId} config={{loginMethods: ["wallet"]}}>
        <AccountBridge
          mode={mode}
          providerState={providerState}
          publishRequestHandler={publishRequestHandler}
        />
      </PrivyProvider>,
    )
  })
}
