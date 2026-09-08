# Regent Identity

Regents owns this Ash domain and its `regent_identity` schema. All four products
consume it using their own database role/connection to **one physical PostgreSQL
database**. Set `config :regent_identity, repo: Product.Repo`. The library starts no
repository, opens no alternate database and changes no product authorization.

Call `sync/1` only with `RegentPrivy.Session.verify/2` evidence during explicit
sign-in or account linking. Read using `get_my_profile(actor: evidence)`, edit
using `edit_profile(profile, attrs, actor: evidence)`, and serialize with
`present/1`. Never construct the actor from request JSON or an unverified cookie.
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

## Disposable verification

Create a uniquely named local database, then set `REGENT_IDENTITY_TEST_DATABASE`
and `REGENT_PRIVY_PATH` to the recorded verifier checkout. Run `mix check`.
The test harness checks its database name before migrating its own schema. It
never resets any existing product database. No production/provider access occurs.

## Cutover status

Local adoption candidates exist for all four products, including `/profile`, the
private API and matching CLI/WebMCP operations. Four real product Repo modules
passed a shared local-database profile/read/edit/concurrent-sync check. No
production account merge or provider configuration is implied.
A verified source-to-canonical mapping, complete database rehearsal and four-origin
Privy canary are required before rollout.

## Shared HTTP contract

A product may forward `/api/v1/profile` to `RegentIdentity.HTTP`, passing
`otp_app: :product_app`. `GET /` reads without creating a row; `POST /sync`
reconciles a verified, explicit sign-in/link event; `PATCH /` accepts only
`display_name` and `wallet_address`. All return `{profile: ...}` on success.
Each request requires `Authorization: Bearer <access token>` and
`privy-id-token: <identity token>` headers; these proofs belong in a credential
adapter, never ordinary WebMCP tool parameters or CLI command-line arguments.

The caller obtains proof through the product's existing Privy bridge. Do not
replace product session revocation, CSRF or payment authorization with this
adapter. Tool registration and product routes are separate adoption work. The
adapter is not mounted automatically, and does not enable CORS or cross-site
cookie sharing. A profile response is private and non-cacheable.

Profile `verified` flags describe the last synchronized signed evidence, not a
live provider lookup or payment authority. Responses include `verification_basis`
and `evidence_issued_at`; explicit link/unlink events must sync before presenting
new status. GET never updates those records. Mounting Phoenix endpoints use `RegentIdentity.BodyReader` to
enforce an 8 KiB profile-body limit before parsing; the adapter also bounds
known profile fields and requires JSON even for already-parsed bodies.

## Release preparation

`mix regent_identity.stage` exports identity and Privy from prepared dependency
snapshots. Set `REGENT_IDENTITY_REVISION` and `REGENT_PRIVY_REVISION` to their full
candidate commits; altered snapshot files are refused. It never runs migrations.
Regents is the single migration owner: explicitly run
`RegentIdentity.Migrator.up(Product.Repo)` only against the identified destination.
It uses `regent_identity_schema_migrations`, separate from product histories.

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
