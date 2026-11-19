# Changelog

## Unreleased

- The tests are gone (19 Nov 2026). `mix check` compiles with warnings as errors and
  checks formatting and the usage rules.
- `RegentPrivy.Proof.pair/1` reads a request's Privy pair: the access token only as
  the bearer and the identity token only as `privy-id-token`, exactly one of each.
  It is the pair `RegentPrivy.Session.verify/2` takes.
- `RegentPrivy.Owners` keeps pages for the Privy accounts an app names. It is a plug
  and an `on_mount` hook over a module the app writes (its owners, who a session is
  signed in as, and whether that sign-in still holds); anyone else gets the app's
  not-found page. An open page checks again on every navigation, press, message
  and background result, and goes on only while the sign-in still names the owner
  it was opened for (not a press or result aimed at a LiveComponent). Both put the
  owner's Privy id in the assign `:owner_privy_user_id`, for the app's actor. A
  signed-in account that is not an owner is logged with its Privy id.
- `RegentPrivy.OwnerSession` answers those two sign-in callbacks from the app's
  cookie session, with no table: `put/2` after the pair is verified, which starts
  the session afresh (a new session id, nothing kept from before, a new forms token
  sent back in `x-csrf-token`) under a live socket id; `sign_out/1`, which drops the
  session and disconnects its open pages; `browser/1`, handed to `startPrivySignIn`.
- `RegentPrivy.ContentSecurityPolicy.sign_in/0` lists the sources Privy's sign-in
  needs, by directive, for an app to add to its own policy.
- The browser half ships in `assets/privy_sign_in.mjs`, copied into an app by
  `mix regent_privy.assets`: `readPrivyPair` (identity token first, then access
  token, never half a pair), `privyPairHeaders`, `privyLoginFailure`, and
  `startPrivySignIn`, a hidden Privy sign-in that posts the pair to the app's
  session path and signs out there, then at Privy only once the server has ended
  the session. It sends the forms token each sign-in's answer hands over. Given the
  server's `session`, it posts Privy's next token again while the same person stays
  signed in, so the sign-in renews quietly.
- Needs `plug` at run time, and `phoenix_live_view`.
- jose 1.11.13 in the lock, which fixes the eight jose advisories of 26 Oct
  (EEF-CVE-2026-65625 to -65632, one high).
- `verify_token/2` and `RegentPrivy.Session` now name two wallets apart:
  `embedded_wallet_address`, the wallet Privy made for the person (its
  `wallet_client_type` is `privy`), and `user_wallet_address`, the most recently
  verified wallet the person brought themselves. Each is nil when there is none.
  `wallet_addresses` is unchanged.
- `wallet_address`, the person's main wallet, is now their own wallet when they
  have one and the Regents embedded wallet otherwise. Before, it was whichever
  wallet Privy verified most recently, so Privy making the embedded wallet during
  a sign-in could take the main wallet (and its ENS name) from the person's own.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. `verify_token/2` drops a catch-all clause
  that Elixir 1.20's type checker proves can never run; every result it returns is
  unchanged. joken 2.7.0.

## 0.2.1

- A verification key that is not a readable PEM (for example one written on a
  single line with literal `\n` in place of line breaks) now returns
  `:invalid_verification_key`. Before, it built a signer with no key and every
  token failed as `:token_verification_failed`.

## 0.2.0

- `wallet_address` is now the wallet Privy verified most recently (the wallet the
  person signed in with), read from each wallet entry's `lv` time, instead of the
  first wallet listed. A wallet entry without a verification time is not wallet
  evidence.

## 0.1.0

- Initial release: `RegentPrivy.verify_token/2` with ES256 signature
  verification, issuer/audience/time-claim validation, and linked wallet
  address extraction.
