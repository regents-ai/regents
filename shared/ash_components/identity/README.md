# Regent Identity

This Ash domain and its `regent_identity` schema are shared by every Regent site. All four products
consume it using their own database role/connection to **one physical PostgreSQL
database**. Set `config :regent_identity, repo: Product.Repo`. The library starts no
repository, opens no alternate database and changes no product authorization.

Call `ensure/1` at sign-in, with the `RegentPrivy.Session.verify/2` evidence, so
every signed-in person has a profile; `sync/1` refreshes it from that evidence
during an explicit sign-in or account linking. Read using
`get_my_profile(actor: owner)`, edit using `edit_profile(profile, attrs, actor: owner)`,
where `owner` is a `RegentIdentity.Owner` (`%{app_id, privy_user_id}`), and
serialize with `present/1`. A site shows each person's chosen name on its own account
resource with the calculation `{RegentIdentity.ProfileName, otp_app: :product_app}`,
which reads only the name, whoever asks. Build the owner only from the site's own
sign-in (`RegentIdentity.Owner.of/1` on verified evidence, the person behind the
site's session, or the person an agent is paired with), never from request JSON.
Shared IDs are additive: existing product IDs and signed payment payloads remain
unchanged. Personal Privy X proof does not replace Autolaunch company-role OAuth.

No wallet is required. One initial linked wallet is selected; multiple wallets
require an explicit choice. Refresh never changes that choice, and an unlinked
selection is returned as unverified. This field does not rewrite product payout
or wallet-signer selection. The latter must be adopted through reviewed product
changes.

The migration runs once, from Regents, with its own migration ledger. Consumers
must not run it from their migration streams. New product destinations must avoid Regents' occupied legacy `autolaunch` schema.
**Do not simply repoint existing databases**: historical public foreign keys,
sequences, sessions, ledgers and product IDs need a rehearsed data reconciliation.

## Cutover status

Local adoption candidates exist for all four products, including a private account page, the
private API and matching CLI/WebMCP operations. Four real product Repo modules
passed a shared local-database profile/read/edit/concurrent-sync check. No
production account merge or provider configuration is implied.
A verified source-to-canonical mapping, complete database rehearsal and four-origin
Privy canary are required before rollout.

## Shared HTTP contract

Contract 2.0.0 (`contracts/profile.openapi.json`). A product forwards
`/api/v1/profile` to `RegentIdentity.HTTP` behind a plug of its own that decides
who is calling from the product's sign-in and puts that person on the request
with `RegentIdentity.HTTP.put_owner(conn, %RegentIdentity.Owner{app_id: ..., privy_user_id: ...})`:

```elixir
pipeline :profile_owner do
  plug MyAppWeb.Plugs.ProfileOwner
end

scope "/api/v1" do
  pipe_through [:api, :profile_owner]
  forward "/profile", RegentIdentity.HTTP
end
```

The API acts for that owner and reads no credential or person from the request
itself; with no owner on the request it answers 401 `authentication_required`.
The product's plug carries the product's own rules: its session cookie, with its
forms (CSRF) token on a change, or an agent the person paired, signing its
request. `GET /` reads without creating a row: a profile is made at sign-in by
`ensure/1`, so before that it answers 404 `profile_not_created`. `PATCH /`
accepts only `display_name` and `wallet_address`. Both return `{profile: ...}`
on success, and every refusal returns `{error: {code, message, hint}}`. A
`display_name` with a hidden character, or over 80 characters, is refused with
`invalid_display_name`: a control character, a line or paragraph separator, or a
format character, such as a text-direction mark, a zero-width space or a soft
hyphen. A zero-width joiner or non-joiner between two visible characters and the
tag characters of a complete flag stay allowed. A `wallet_address` must be one of
the verified linked wallets the profile holds from its last sign-in.

The browser client (`assets/profile_client.mjs`, copied into a product by
`mix regent_identity.assets`) sends the page's session cookie and, on a change,
the forms token the product gives it in `x-csrf-token`. The adapter is not
mounted automatically, and does not enable CORS or cross-site cookie sharing. A
profile response is private and non-cacheable.

Profile `verified` flags describe the last synchronized signed evidence, not a
live provider lookup or payment authority. Responses include `verification_basis`
and `evidence_issued_at`; explicit link/unlink events must sync before presenting
new status. GET never updates those records. Mounting Phoenix endpoints use `RegentIdentity.BodyReader` to
enforce an 8 KiB profile-body limit before parsing; the adapter also bounds
known profile fields and requires JSON even for already-parsed bodies.

## Migrations

Regents is the single migration owner: explicitly run
`RegentIdentity.Migrator.up(Product.Repo)` only against the identified destination.
It uses `regent_identity.schema_migrations`, separate from product histories.

## One-database cutover boundary

The local proof exercises shared profiles. Moving existing product data remains
blocked on an identified, inspected source and destination and a restore-tested
copy. Do not point four legacy migration streams at one database: Regents and
Autolaunch both own incompatible public `linked_identities` and
`session_authorities`, and all products have a public migration ledger. Preserve
legacy IDs and signed payment/claim records; map them to the canonical profile
rather than rewriting their identifiers.

Use separate product roles/schemas (`regents_app`, `autolaunch_app`, `patchbay_app`,
`techtree_app`) plus `regent_identity`. Existing explicitly named legacy schemas
must be inventoried as well. AshPostgres Repo `default_prefix/0`, unqualified SQL
search paths, foreign keys, sequences and migration ledgers all need a tested
cutover together. No destructive or historical migration replay is supplied here.

All four deployments must use the same Privy application and verification key,
with their origins registered and X enabled. Profile IDs are canonical; site
cookies and local session revocation remain product-owned. A real four-origin
sign-in/X-link canary is required before claiming provider integration complete.

Profile WebMCP installation reports `unsupported`, `registering`, `ready`, `failed`
or `stopped` in `document.documentElement.dataset.profileWebmcp` and the
`regent:profile-webmcp` event. The returned cleanup function also exposes `status`,
`ready` and explicit `retry()`. All registrations must succeed before tools execute;
failure aborts only this installation. Page navigation retries normally. Native
support remains experimental pending an actual host canary.
