# Changelog

## 0.1.0 (unreleased)

- Several profiles in one app may hold the same X account (19 Nov 2026): migration
  `20261119204035_shared_x_accounts` drops the unique index on a profile's app and
  X account, and its way back rebuilds it.

- The tests and their database are gone (19 Nov 2026). `mix check` runs in dev
  against `RegentIdentity.Repo` in `dev/`, which no `:prod` build compiles, and
  compiles with warnings as errors and checks unused locks, formatting, Credo and the
  usage rules.

- Profile contract 2.0.0: `RegentIdentity.HTTP` acts for the owner the site puts on
  the request with `RegentIdentity.HTTP.put_owner/2`, a `RegentIdentity.Owner`
  (`%{app_id, privy_user_id}`). The site decides who is calling from its own sign-in,
  in a plug before the forward: its session, or an agent the person paired. The API
  reads no credential or person from the request; with no owner it answers 401
  `authentication_required`, whose hint now names both ways in. It routes `GET /` and
  `PATCH /` only: `POST /sync` is gone, with its `identity_evidence_conflict` refusal,
  and so are the `x-privy-user-id` header and `profile_unconfigured` (the API reads no
  Privy settings). `forward` takes no `otp_app`. A profile is made at sign-in by
  `ensure/1`, and the 404 `profile_not_created` hint says so.
- `get_my_profile/1` and `edit_profile/3` take a `RegentIdentity.Owner` as their
  actor (policy check `RegentIdentity.OwnerActor`); `RegentIdentity.Owner.of/1` names
  the owner of verified sign-in evidence. `sync/1`, `ensure/1` and the `:register`
  and `:refresh` actions still take `RegentPrivy.Session` evidence. A chosen
  `wallet_address` must be one of the verified wallets the profile holds from its last
  sign-in.
- The browser client `createProfileClient({csrfToken, fetch})` sends the page's
  session cookie (`credentials: "same-origin"`) and, on `update`, the forms token in
  `x-csrf-token`; its operations are `get` and `update`. `loadProfileAction` is gone,
  and the profile tools are `profile_get` and `profile_update`.
  `RegentIdentity.BodyReader` caps the body on `/api/v1/profile` alone.
- `RegentIdentity.ensure/1` gives a verified person their profile at sign-in when
  they have none and leaves an existing one as it is. `RegentIdentity.profile_id/2`
  reads a person's profile ID by app and Privy user, for a server acting for them
  without their session (a paired agent paying for its person). The `:person`
  read behind it and the `:names` read behind `RegentIdentity.ProfileName` are
  closed to every actor, so no signed-in person or agent can read another's
  profile through them.

- jose 1.11.13 in the lock, which fixes the eight jose advisories of 26 Oct
  (EEF-CVE-2026-65625 to -65632, one high).
- ash_postgres comes from Regent's copy of 2.15.2 (regents-ai/ash_postgres at
  cc886ab3), which carries ash-project/ash_postgres#910: upserts are written to the
  schema the site's repo picks, as on 2.13.0. It clears the two 2.13.0 advisories.
  Ash 3.37.2, ash_sql 0.8.4.
- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. phoenix 1.8.16.
- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/identity`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- `RegentIdentity.ProfileName`: the calculation a site puts on its account
  resource to show the name a person set in their shared profile. Each site
  used to keep its own copy of the profiles table to read it.
- A display name may not hold hidden characters (founder, 2026-10-19): control
  characters, line and paragraph separators, or format characters, which include
  the marks that turn the text around them to run the other way, zero-width
  spaces, the byte-order mark, the word joiner and the soft hyphen. A zero-width
  joiner or non-joiner stays allowed between two visible characters (emoji joins,
  Persian script), and tag characters inside a complete flag, from U+1F3F4 to
  U+E007F. `PATCH /` refuses any other with the code `invalid_display_name`;
  letters in any script, accents and emoji stay allowed. The rule is
  `RegentFormat.Name`, shared with agents' names; `regent_format` is a new path
  dependency.
- The name check now names six cases a looser rule once let through: tag
  characters outside a flag, a zero-width space, a joiner before a space, and
  three broken flags (a stray tag-block character, a flag that ends twice, a flag
  followed by a joiner). Each of six looser rules fails `test/http_test.exs`.
