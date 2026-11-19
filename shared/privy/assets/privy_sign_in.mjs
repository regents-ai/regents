// Privy sign-in for Regent apps: the browser half of RegentPrivy.Proof,
// RegentPrivy.Session and RegentPrivy.OwnerSession. The app supplies react,
// react-dom and @privy-io/react-auth; `mix regent_privy.assets` copies this file
// into the app's assets/vendor/regent_privy.
import {PrivyProvider, getIdentityToken, useLogin, usePrivy, useToken} from "@privy-io/react-auth"
import React from "react"
import {createRoot} from "react-dom/client"

const failed = () => new Error("Sign in could not be completed.")

// Privy's two tokens have two different jobs: the access token proves this
// browser's Privy session and the identity token carries the signed accounts
// that session is entitled to. The evidence is asked for first and the session
// proof second, so the proof is never older than the evidence it is offered
// with. A half pair is never returned. `requireCurrent` runs after each read and
// throws when the caller's attempt has gone stale.
export async function readPrivyPair({getIdentityToken, getAccessToken, requireCurrent = () => {}}) {
  requireCurrent()
  const identityToken = await getIdentityToken()
  requireCurrent()
  const accessToken = await getAccessToken()
  requireCurrent()

  if (!identityToken?.trim() || !accessToken?.trim()) throw failed()
  return {accessToken, identityToken}
}

// Each token travels in its own header, never in the URL or the body.
export function privyPairHeaders({accessToken, identityToken}) {
  return {authorization: `Bearer ${accessToken}`, "privy-id-token": identityToken}
}

// Privy's login error codes a person can cause, and what each is reported as.
const loginFailures = {
  exited_auth_flow: "flow_closed",
  client_request_timeout: "request_timeout",
  invalid_message: "invalid_message",
  unable_to_sign: "unable_to_sign",
}

export function privyLoginFailure(error) {
  return loginFailures[typeof error === "string" ? error : ""] ?? "provider_error"
}

function SignIn({sessionPath, csrfToken, session, onSignedIn, onRenewed, onFailure, publish}) {
  const privy = usePrivy()
  const opened = React.useRef(false)
  // Whose sign-in the server holds ({id, current}), or null.
  const held = React.useRef(session)
  // Read by callbacks Privy keeps from its first render.
  const latest = React.useRef({})
  // Each sign-in starts a fresh session with a new forms token, which its answer
  // carries; the next post and the sign-out send that one.
  const forms = React.useRef(csrfToken)

  const post = pair =>
    fetch(sessionPath, {
      method: "POST",
      credentials: "same-origin",
      headers: {...privyPairHeaders(pair), "x-csrf-token": forms.current},
    }).then(response => {
      if (response.ok) forms.current = response.headers.get("x-csrf-token")
      return response
    })

  // Privy's next token renews the sign-in quietly, but only for the person the
  // server already holds, so a Privy session left by someone else never signs
  // them in. A sign-in that had ended reloads the page as a sign-in does.
  const renew = () => {
    const owner = held.current
    const {privy, getAccessToken} = latest.current
    if (opened.current || !owner || !privy.authenticated || privy.user?.id !== owner.id) return

    readPrivyPair({getIdentityToken, getAccessToken})
      .then(post)
      .then(response => {
        if (!response.ok) return
        held.current = {id: owner.id, current: true}
        owner.current ? onRenewed() : onSignedIn()
      })
      .catch(() => {})
  }

  const {getAccessToken} = useToken({onAccessTokenGranted: () => renew()})

  const {login} = useLogin({
    onComplete: ({user}) => {
      if (!opened.current) return
      opened.current = false

      readPrivyPair({getIdentityToken, getAccessToken})
        .then(post)
        .then(response => {
          if (!response.ok) return onFailure("session_exchange")
          held.current = {id: user.id, current: true}
          onSignedIn()
        })
        .catch(() => onFailure("session_exchange"))
    },
    onError: error => {
      if (!opened.current) return
      opened.current = false
      onFailure(privyLoginFailure(error))
    },
  })

  latest.current = {privy, login, getAccessToken}

  // The handle is published once, and always acts on Privy's latest state.
  React.useEffect(() => {
    if (!privy.ready) return

    // A page opened after the sign-in ended renews it at once; a current one
    // waits for Privy's next token.
    if (held.current?.current === false) renew()
    publish({
      // A Privy session this browser still remembers belongs to whoever signed
      // in before, so it is logged out first and never reused.
      async signIn() {
        if (opened.current) return
        if (latest.current.privy.authenticated) await latest.current.privy.logout()
        opened.current = true
        latest.current.login()
      },
      // Privy is logged out only once the server has ended the session; a
      // refusal rejects, so the page can say so and the person can try again.
      async signOut() {
        const response = await fetch(sessionPath, {
          method: "DELETE",
          credentials: "same-origin",
          headers: {"x-csrf-token": forms.current},
        })
        if (!response.ok) throw new Error("Sign out could not be completed.")
        held.current = null
        await latest.current.privy.logout()
      },
    })
  }, [privy.ready])

  return null
}

// Starts Privy in a hidden element and resolves, once Privy is ready, to
// `{signIn, signOut}`. Sign-in posts the pair to `sessionPath` and calls
// `onSignedIn`; sign-out deletes the session there, then logs Privy out, and
// rejects without logging Privy out when the server refuses. A failure is
// reported to `onFailure` by its reason, and a person who closes the sign-in
// window is reported as "flow_closed". `csrfToken` is the page's forms token,
// used until a sign-in's answer hands over the next one. `session` is the
// sign-in the server holds (RegentPrivy.OwnerSession.browser/1): while the same
// person stays signed in at Privy, each new Privy token is posted again, calling
// `onRenewed`, and a sign-in that has ended is renewed as a sign-in, calling
// `onSignedIn`.
export function startPrivySignIn({
  appId,
  sessionPath,
  csrfToken,
  session = null,
  config = {},
  onSignedIn = () => window.location.reload(),
  onRenewed = () => {},
  onFailure = () => {},
}) {
  const host = document.createElement("div")
  host.hidden = true
  document.body.append(host)

  return new Promise(resolve => {
    createRoot(host).render(
      React.createElement(
        PrivyProvider,
        {appId, config},
        React.createElement(SignIn, {
          sessionPath,
          csrfToken,
          session,
          onSignedIn,
          onRenewed,
          onFailure,
          publish: resolve,
        }),
      ),
    )
  })
}
