# RegentPrivy

Shared Privy sign-in for Regent Elixir apps: token verification, Privy's server
calls, the request pair, owners-only pages and the browser sign-in.

`RegentPrivy.verify_token/2` verifies the ES256 signature against the app's
Privy verification key, validates issuer, audience, and time claims, and
returns the verified claims, the Privy user id, and normalized linked wallet
addresses. `user_wallet_address` is the person's own wallet, `embedded_wallet_address`
the Regents wallet Privy made for them, and `wallet_address`, their main wallet, is
their own wallet when they have one and the Regents wallet otherwise. Apps pass
their own Privy configuration per call:

```elixir
RegentPrivy.verify_token(token,
  app_id: "my-privy-app-id",
  verification_key: pem
)
#=> {:ok, %{claims: %{...}, privy_user_id: "did:privy:...",
#=>         wallet_address: "0x...", wallet_addresses: ["0x..."]}}
```

This library holds no configuration or secrets and never logs token contents.

## Paired authentication evidence

Use `RegentPrivy.Session.verify(%{access: access_token, identity: identity_token},
app_id: app_id, verification_key: public_key)` at server authentication boundaries.
It verifies both signatures and audiences, then binds the subject and session and
rejects confused token roles. Identity tokens may omit `sid`; access tokens may not.
The returned struct retains signed linked X identity and token expiry without raw
claims. It authenticates social-only users without granting payment permissions.

All four sites must use the same configured Privy application to identify the same
subject. Products still own their sessions, authorization and persistence. Never
merge old users across different Privy applications by wallet or X handle. Wallet
list order is evidence order, **not** an instruction to change a stored payout
address; preserve explicit verified wallet selection in the owning profile.

## Signing in on a page

- `RegentPrivy.Proof.pair(conn)` reads the pair a sign-in request carries: the
  access token as the bearer and the identity token as `privy-id-token`, never in
  a URL or a body. Pass it to `RegentPrivy.Session.verify/2`.
- `RegentPrivy.ContentSecurityPolicy.sign_in()` lists the sources Privy's sign-in
  loads, by directive. Add each list to that directive on the pages that can sign
  someone in, and nowhere else.
- `RegentPrivy.Owners` keeps pages for the Privy accounts the app names. The app
  writes one module with the behaviour's three callbacks (`owners/0`,
  `signed_in/1`, `still_signed_in/1`) and names it twice:

  ```elixir
  plug RegentPrivy.Owners, sign_in: MyAppWeb.Owner, router: MyAppWeb.Router

  live_session :owner, on_mount: [{RegentPrivy.Owners, MyAppWeb.Owner}] do
    ...
  end
  ```

  Anyone else gets the app's not-found page; a signed-in account that is not an
  owner is logged by its Privy id, once for the request. A page that is open
  checks again on every navigation, press, message and background result it
  receives, and goes on only while the sign-in still names the owner it was opened
  for. The endpoint's socket must pass `connect_info: [session: ...]`.

  Both put the verified owner's Privy id in the assign `:owner_privy_user_id`
  (`conn.assigns` and `socket.assigns`), so the app builds its actor from it.

  A press or background result aimed at a LiveComponent (`phx-target={@myself}`)
  skips the page's hooks and is not checked. Pages behind `Owners` handle their
  presses and start their background work on the page itself. A background result
  is checked when it comes from `start_async`; an `assign_async` result fills its
  assigns without the page's hooks, and the next press or navigation checks again.
- `RegentPrivy.OwnerSession` keeps the sign-in in the app's cookie session, with
  no table, and answers `signed_in/1` and `still_signed_in/1` for the app's
  owners module by `defdelegate`. The sign-in ends when the earlier of the two
  tokens expires.
  - The sign-in route verifies the pair and calls `OwnerSession.put(conn,
    session)`. That starts the session afresh: a new session id, nothing kept from
    before, and a new forms token, sent back in the answer's `x-csrf-token`
    header. The forms token the page held before stops working.
  - The sign-in route tells two failures of `RegentPrivy.Session.verify/2` apart.
    `{:error, {:configuration, _}}` and `{:error, {_stage, :invalid_verification_key}}`
    mean the app's own Privy settings are missing or unreadable: answer 503 and
    leave the session as it is, so a wrong setting does not sign everyone out.
    Every other error means this browser's tokens are not good: answer 401.
  - The sign-out route calls `OwnerSession.sign_out(conn)`, which also
    disconnects that sign-in's open pages.
  - `OwnerSession.browser(session)` is what the page hands `startPrivySignIn` as
    `session`.
- The browser half is `assets/privy_sign_in.mjs` (types in `privy_sign_in.d.mts`).
  Add `regent_privy.assets` to the app's `assets.build` and `assets.deploy` aliases;
  it copies both into `assets/vendor/regent_privy/`, which the app leaves out of
  git. The app supplies `react`, `react-dom` and `@privy-io/react-auth`.
  - `readPrivyPair({getIdentityToken, getAccessToken, requireCurrent})` reads the
    identity token, then the access token, and returns both or throws.
  - `privyPairHeaders(pair)` gives the two headers `RegentPrivy.Proof.pair/1` reads.
  - `privyLoginFailure(error)` names a Privy login error, such as `flow_closed`.
  - `startPrivySignIn({appId, sessionPath, csrfToken, session})` starts Privy in a
    hidden element and resolves to `{signIn, signOut}`. Sign-in posts the pair to
    `sessionPath`; sign-out deletes the session there, then logs Privy out, and
    rejects without logging Privy out when the server refuses. `csrfToken` is the
    page's forms token; after each sign-in it sends the one the answer handed
    over. While the person the server holds stays signed in at Privy, each new
    Privy token is posted again (`onRenewed`), and a page opened after the
    sign-in ended renews it as a sign-in (`onSignedIn`, a reload by default).

`mix check` compiles, checks formatting and checks the usage rules without changing lockfiles.
