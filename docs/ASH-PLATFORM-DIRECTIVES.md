# Regent Founder Constitution — ash-platform candidate

This is the single human-readable statement of what `ash-platform` is meant to
be. It consolidates the founder directives and the decisions made during the
greenfield and interface grilling sessions through 2026-07-10.

It describes product intent and acceptance principles, not implementation
status. Beads owns execution state only. Current shipping status belongs in
the machine-readable stack/repo contracts and owning interface contracts.
Source contracts own exact public interfaces. The implementation may improve
as we learn, but it must not quietly change a founder directive.

## Authority and interpretation

This document is the candidate successor to the existing workspace
`founder.md`. Until Sean reviews and explicitly approves the replacement,
`founder.md` remains the active stack constitution. After approval, this text
will replace it through a separate, reviewed workspace-governance change; the
draft in `ash-platform` remains the comparison copy during implementation.

Old tickets, specs, screenshots, handoffs, and code are historical evidence.
They are not requirements merely because they already exist. Functionality is
admitted to `ash-platform` only after the founder and Chief explicitly accept
the capability. When an old record conflicts with a newer directive here, the
newer directive wins.

Metaprogramming guidance must say the same thing plainly: historical tickets
and documents record why earlier work happened, but they are not sacred design
authority for the greenfield app. After `ash-platform` is stable, Sean and the
Chief will review those records together, consolidate the few decisions that
still matter, delete obsolete material, and create a smaller current set.

Adopting this replacement also requires one explicit machine-contract
reconciliation: `metaprogramming/stack.yaml` and active repo contracts must
name `ash-platform` as the web owner and remove retired messaging/XMTP
ownership. This draft does not silently override contradictory machine state.

The sacred invariants are deliberately small:

- Preserve the four protected datasets named below.
- Preserve the core founder capabilities: what humans and agents must be able
  to accomplish across Formation, Autolaunch, Techtree, and Regent Ops.
- Preserve identity, money, and signing safety.
- Preserve especially strong product ideas, but allow the route, UI, domain,
  and implementation shape to improve.

Everything else may be rewritten or deleted when a simpler, more correct
greenfield design earns its place.

## Regent stack constitution

Regent is one product family with distinct surfaces and responsibilities:

- `ash-platform` is the public web application at `regents.sh`, containing
  Formation, Autolaunch, Techtree, and Regent Ops.
- Regents CLI is the canonical direct control surface for agents and
  operators. It remains the primary creation/publishing path where this
  document says the web is read-only.
- Shared SIWA and identity utilities own signed-agent authentication and
  receipts. Browser-human Privy sessions never substitute for that rail.
- iOS is the wallet-first mobile surface and owns its mobile wallet/signing
  boundary. Mobile and web may share a human Privy account without sharing
  session or transport contracts.
- Fly Sentinel is a private operational view. It never becomes an owner of
  product workflow, identity, billing, or onchain state.
- The design system owns reusable visual language, not product authority.

The retained non-web capabilities are intentionally small and concrete:

- Regents CLI lets an operator or SIWA agent set up and inspect identity,
  connect to its Regent, manage its own runtime, publish and evaluate Techtree
  work, prepare Autolaunch work, and obtain repeatable machine-readable
  reports. It does not silently sign value actions.
- iOS lets a human sign in, see the active Regent, inspect the linked wallet,
  receive, send, buy, cash out, and review wallet history, and explicitly
  approve supported wallet actions. It does not replace the full-featured
  mobile web application.
- Fly Sentinel shows private health/readiness, errors, machines, metrics, and
  links to the owning operational systems. It does not copy product data into
  an operations database.

**Source ownership.** The owning OpenAPI contract defines HTTP behavior; the
owning CLI contract defines shipped terminal behavior; shared-service and
JSON-RPC contracts define their respective boundaries; the chain manifest
defines admitted prepared onchain actions. Generated copies have one owner and
are never edited as independent truth. Onchain state wins for balances,
ownership, staking, and settlement. Product databases win for their workflow
state. Local CLI/browser state and operations snapshots are downstream.

**Production data.** Preserve live protected rows in place. New Techtree or
Autolaunch data is additive and imported only through a named, approved plan.
Do not replay old product migrations merely because they exist. Any production
database migration, import, reset, or deletion requires explicit approval and
verified recovery evidence.

**Identity.** Human browser accounts, SIWA agent identities, wallet ownership,
and public display labels are separate concepts. A friendly name, ENS name,
nameclaim, profile slug, or mirrored wallet never becomes signing authority.
Every capability names the principal type it accepts and denies the others by
default.

A SIWA agent identity is grounded in its verified wallet plus the onchain
identity tuple `chain_id`, registry address, and token id. The intended stable
cross-product key is `agent_id`, derived from and resolvable back to that
verified tuple through an owning contract. A display name or product-local id
never substitutes for it.

**Secrets.** Secrets are owned by purpose, not copied into one universal app:
billing secrets stay with billing; mobile wallet/payment secrets stay with the
mobile backend; shared signing material stays with the SIWA service;
operator-local material stays on the operator host; read-only operational
tokens stay with the private operations surface. Secrets never enter source,
public output, logs, prepared action metadata, or browser bundles.

**Money.** Servers may prepare, register, verify, confirm, and reconcile value
actions. A user wallet, operator wallet, or contract-defined path signs and
moves value. No server redirects value outside the explicitly displayed
beneficiary/treasury/staker/claimant path. A submitted transaction is not
success; the expected-chain receipt and an onchain reread decide completion.

**Status honesty.** Every major capability is labelled `live`, `beta`,
`preview`, or `planned` in the owning machine/interface contract. Product
intent and current shipping state are kept distinct. Beads never supplies
shipping status. A polished placeholder does not count as a working
capability.

**Hard cutovers.** Regent is pre-launch. Prefer one current contract, route,
resource, and state owner. Do not preserve old aliases, adapters, fallbacks,
dual shapes, or compatibility branches unless the founder explicitly admits a
real external compatibility requirement.

## Product outcome

**AP-001 — Small canonical application.** Build a separate Phoenix, LiveView,
and Ash application around approved founder capabilities. Do not reproduce the
size or architecture of the old Platform application.

**AP-002 — Physical separation.** `ash-platform/` is a sibling application and
independent Git repository. The existing `platform/` application is treated as
`old-platform`: quarantined, runnable evidence. `ash-platform` has no runtime,
code, database-context, migration, or compatibility dependency on it.

**AP-003 — Admission by confirmation.** Apart from the explicitly approved
close ports, old functionality enters `ash-platform` only after the founder
and Chief confirm it. The usual sequence is targeted reconnaissance, an
accepted capability boundary, a vertical implementation, and direct proof.

**AP-004 — First playable milestone.** The first locally testable product
milestone is:

1. the approved route catalog and persistent shell;
2. verified browser-human Privy sign-in and sign-out;
3. the working REGENT staking experience; and
4. the working NFT-to-REGENT redemption experience.

Privy, staking, and redemption should preserve the verified old-platform
behavior closely because those paths are subtle and already work. They still
receive clean Ash ownership and do not bring unrelated old architecture with
them.

## Protected data and truth

**AP-010 — Four protected datasets.** These are the only existing database
tables that must be preserved as hard invariants:

- `platform.platform_human_users`
- `platform.basenames_mints`
- `platform.basenames_mint_allowances`
- `platform.basenames_payment_credits`

Each protected table may be admitted independently only through its explicit
Ash resource relationship, actor, authorization, and no-data-loss plan. One
table's unfinished modeling does not block approved use of another. Never
create a duplicate store, replay its historical migrations, or connect a
generic application data layer to these tables by accident.

**AP-011 — Truth order.** Onchain state owns balances, ownership, staking, and
value settlement. Product databases own product workflow state. Contract YAML
owns public interfaces. Local browser and CLI state are downstream.

**AP-012 — Value signatures.** Servers may read, prepare, register, verify,
confirm, and reconcile money actions. A user wallet, operator wallet, or
contract-defined path signs and moves value. The server never silently signs
or redirects value.

## Greenfield engineering rules

**AP-020 — Vertical capabilities.** Slice work by founder capability or user
journey. A capability slice may change contracts, producers, consumers, UI,
and tests together. Avoid horizontal “finish all resources” or vague future
“consumer cutover” stages.

**AP-021 — Named domain interfaces.** Callers use intent-named interfaces such
as `reserve_runtime_spend`, `start_formation`, `publish_node`, or the exact
staking/redeem interfaces approved later. These are normally Ash domain code
interfaces. Generic CRUD and raw Repo access do not become the application
boundary.

**AP-022 — Resources represent real state.** Do not create ceremonial Ash
domains or resources merely to demonstrate Ash. A resource appears when an
approved capability has a real state owner, actions, policies, and tests.

**AP-023 — Deny by default.** The first authenticated resource is policy
protected and deny-by-default. The actor is supplied when constructing the
Ash query or changeset. Browser-human Privy identity and SIWA agent identity
remain different principal types and different authentication rails.

**AP-024 — One owner per concept.** Human identity, agent identity, profile
display, billing credit, route metadata, and each product record have one
canonical physical owner. Keep a facade only when it performs real
multi-resource or external-service orchestration. Delete pass-through facades,
compatibility walls, adapters, aliases, and dual shapes.

**AP-025 — Current stable dependencies.** Immediately before generation and
each lockfile commit, query official Hex/npm sources and install the latest
stable compatible release of every dependency the app actually uses. Exclude
prereleases without explicit approval. Record the query, observation time,
locked version, purpose, outdated result, audit result, and any unavoidable
transitive constraint. Do not copy old-platform lockfiles or add unused
packages.

**AP-026 — Quality from the first shell.** Establish budgets and executable
proof early: route authority, deep links, cancellation, Back/Forward,
keyboard, mobile, reduced motion, failure isolation, dependency firewalls,
rendered size, JavaScript, CSS, and query counts. A green narrow test does not
justify a broad completion claim.

## Canonical route map

The public homepage is outside the persistent application shell:

- `/`

The initial shell owns exactly these routes:

- `/app`
- `/formation`
- `/regents/:slug`
- `/techtree`
- `/techtree/:tree_slug`
- `/techtree/nodes/:node_id`
- `/autolaunch`
- `/autolaunch/auctions`
- `/autolaunch/auctions/:auction_id`
- `/autolaunch/tokens`
- `/autolaunch/tokens/:token_id`
- `/autolaunch/create`
- `/stake`
- `/redeem`

**AP-030 — Route authority.** One typed route catalog owns path identity,
precedence, app identity, labels, canonical root, contextual navigation,
header controls, background slot, transition kind, validation, and local
presentation state. The Phoenix router and generated Design handoff must
mechanically converge with that owner.

The catalog exposes one stable app/background key for each of Formation,
Autolaunch, Techtree, and Regents Labs. It never emits theme-specific asset
URLs or route-specific background families. It also owns the motion scope for
each destination (`none`, `shell-only`, or `shell-and-stage`) and whether that
destination may be snapshotted for a presentation transition.

**AP-031 — Techtree precedence.** `/techtree/nodes/:node_id` wins before the
dynamic tree route. `nodes` is reserved and invalid as a tree slug.

**AP-032 — No hidden route families.** Formation panels are local presentation
state. Techtree Map/List is URL-addressable presentation state on the same
canonical route: `/techtree/:tree_slug?view=map|list`. It is not a duplicate
route family. Missing `view` defaults to `map`; invalid values are rejected or
canonicalized to `map` at the route-metadata boundary. Only the two canonical
values are emitted. Docs and other old routes are not implicitly admitted.

## Persistent shell

**AP-040 — App selector.** The upper-left control is one visually obvious,
one-line selector: canonical crown, current app label, and chevron. The four
labels are Formation, Autolaunch, Techtree, and Regents Labs. Selecting one
always opens its canonical root; there is no per-app last-route memory.

**AP-041 — Account control.** The upper-right target is separate from the app
selector. It shows `Sign In` while logged out. While signed in, it shows the
address-derived avatar plus resolved profile/ENS/wallet label and opens the
account menu. That menu contains Profile only when the account has its one
public Regent record, then Settings, then Log Out. Appearance choices live on
the Settings page rather than in the persistent header or account menu. There
is no “Public workspace” label and no combined app/account disclosure.

**AP-042 — One Regent per account.** A human account has one primary Regent.
The persistent shell has no top-level Regent switcher.

**AP-043 — App-local header.** Header information, search, status, and actions
belong only to the active app. Autolaunch and Techtree may expose search.
Formation and Regents Labs do not reserve an empty search field.

**AP-044 — Contextual navigation.** Desktop and tablet use a fixed,
continuously visible sidebar with no collapse, icon-only mode, hover expansion,
or remembered width. Mobile uses a temporary accessible menu without reducing
features.

The exact contextual navigation is:

- Formation: Overview, Cloud, Hermes Skills.
- Autolaunch: Auctions, Tokens, Create.
- Techtree: the five named seed trees in the order recorded below. Each row
  exposes Map and List selectors.
- Regents Labs: Overview, Stake, Redeem, Profile.

**AP-045 — One scroller.** The shell has one internal content scroller. Header
and desktop sidebar remain fixed. Every route, app-root navigation, Back, and
Forward starts at the top; prior route scroll offsets are not restored. Local
tabs/filters preserve position only while it remains valid. Async content,
status changes, and real-time inserts never force-scroll the reader.

For Techtree, switching Map/List on the same tree uses replace semantics,
creates no Back-stack entry, and preserves scroll. Changing trees is genuine
navigation, carries the active or explicitly selected view, and starts at the
top.

**AP-046 — Failure isolation.** The shell stays visible and interactive while
destination content loads, is empty, or fails. Only the destination region
shows loading/error/retry state. App selector, account, and unaffected
navigation remain usable.

**AP-047 — Mobile parity.** Mobile web has the same routes, capabilities,
visibility, and permissions as desktop. It may simplify motion and hand off to
a wallet app for signing, but it does not require or redirect to iOS.

The app shell has no global footer. Homepage alone may have a conventional
footer. Utilities and the sparse ambient motif belong at the bottom of the
desktop sidebar or mobile menu.

## Navigation and motion

**AP-050 — Immediate authority.** URL and application state commit
immediately. Motion never delays or gates navigation. Navigation is
cancellable, latest-destination-wins, and native Back/Forward remains
authoritative.

**AP-051 — Direct loads are honest.** A direct load, refresh, or deep link
renders the correct destination app, background, sidebar, content, and local
presentation immediately. Do not fabricate an outgoing scene. A short opacity
reveal is allowed after correct content is already the default.

**AP-052 — App-switch choreography.** Full-scene motion is reserved for
switching among the four apps. The URL changes immediately; old sidebar and
content regions move slightly downward and fade; SVG backgrounds crossfade;
incoming regions enter from their nearest horizontal edge, edge-first and
center-last. The header frame stays fixed and only app-local header controls
crossfade. Use five to eight semantic regions, not per-card cascades. Target
250–280 ms with no blur, morph, bounce, overshoot, or large travel.

**AP-053 — Quiet local changes.** Intra-app navigation uses a short
content-only transition. Tabs, filters, sorting, pagination, comments, and
status updates do not trigger scene travel. Techtree’s vertical Map/List panel
is the approved exception.

**AP-054 — Accessibility.** Reduced-motion and keyboard-triggered navigation
switch immediately without travel. Cancellation cleans up every disposable
visual copy. Motion never owns product state, route authority, or focus.

The shell has one interactive LiveView stage and one dedicated, short-lived
presentation portal outside that stage. Any outgoing copy in the portal is
inert, `aria-hidden`, pointer-free, and stripped of ids, names, form ownership,
references, LiveView/hook/event attributes, and all interactive semantics.
There is never a permanent second tree. One shell transaction/controller owns
the motion lifecycle, is latest-intent-wins, and restores the exact final
authoritative state on cancellation, replacement, failure, reduced motion,
keyboard navigation, and completion.

Anime.js is the approved motion library. Use the current stable release and
the installed Regent Anime.js skill for lifecycle, interruption, cleanup, and
LiveView-hook behavior.

## Theme, material, and voxel language

**AP-060 — Theme.** The Settings page offers exactly System, Light, and Dark.
The persistent header and account menu do not duplicate those controls. The
choice persists locally. System follows later operating-system changes. Theme
changes use only a 140–180 ms color/background crossfade, with no travel,
scale, blur animation, or layout shift. Reduced motion changes immediately.

**AP-061 — Structural material.** All four apps share one high-opacity
liquid-glass material system: one fill recipe, restrained gradient strokes,
consistent elevation, and readable contrast over the SVG grid. The stroke is an
edge treatment, not a glow. Product identity comes from the background, accent,
selected state, mark, and content—not four panel recipes.

The founder's 2026-08-26 product framing supersedes the earlier shared neutral
ground. Each family now sits on its own product ground: Regent routes on
Charcoal under Platinum, Autolaunch on Tangerine Tango under black with
Platinum and Powder Blue highlights, and Techtree on Powder Blue under
Charcoal. The ground answers to the app, never to the Light or Dark choice;
that choice may vary only derived material elevation. Every one of these colors
comes from the shared Regent design system. Ash defines none of its own.

Use glass only for major structural surfaces: header, contextual navigation,
primary stage, major secondary rail, and dialogs. Lists, comments, inputs,
buttons, tabs, tables, and small cards use simpler neutral surfaces and
hairlines. Avoid glass-on-glass nesting.

**AP-062 — Square geometry.** Structural radii are 0–4 px. Controls and focus
rings are square. Circles are reserved for genuinely circular content such as
avatars, token marks, status dots, radios, or spherical art. No pill-shaped or
rounded-blob glass.

**AP-063 — Voxels.** Routine component interactions use sparse 2D voxels as
300–500 ms edge/corner responses to meaningful state. At most one
low-frequency ambient cluster appears in the sidebar/menu utility area. No
constant operational, wallet, or error motion. 3D voxels are reserved for the
homepage, app switching, or one shared sidebar/footer layer—never a canvas per
component. Every use has a static 2D fallback.

Voxel palettes use the active app accent plus the shared product colors. The
founder's 2026-08-26 product framing supersedes Techtree's biological green
secondary; Techtree's biological accent is now Tangerine Tango. Do not use a
cross-product rainbow or decorative status colors.

**AP-064 — Background assets.** The founder will supply separate light/dark
SVG cutting-mat backgrounds for each app. The founder's 2026-08-26 product
framing supersedes the earlier eight-value light/dark guide table. Guides are
guide/grid colors, not full background fills, and each one is the active app's
shared accent: Powder Blue on Regent routes, Tangerine Tango on Formation,
Powder Blue on Autolaunch, and Charcoal on Techtree. A guide follows the app,
not the Light or Dark choice.

Preserve the cutting-mat opacity rhythm: faint fine grid, stronger medium
grid, and controlled primary guides. Do not restate these colors anywhere in
`ash-platform`; read them from the shared design system.

A typed Design asset manifest resolves the route catalog's four stable app
keys against the effective System/Light/Dark theme to exactly these eight
founder-supplied SVGs. Every route inside an app uses that app's background.
The background stays stable during intra-app navigation and crossfades only
when the app key genuinely changes. Do not fabricate substitute artwork,
route-specific slots, or theme-specific URLs in server metadata.

**AP-065 — Homepage storytelling and hero.** Use the strongest content density
and product storytelling from the old Platform homepage, but use the approved
Prime-inspired marketing header, mat hero, four product tabs, and four
principal product chapters. Do not require literal pixel parity with the old
page. This is presentation evidence only; retired messaging, stale product
claims, fabricated live data, unadmitted routes, and old runtime dependencies
do not come with it.

The hero uses the canonical repo asset
`priv/static/images/home/hero-bg-dark.svg`, originally supplied as
`hero-bg-dark.svg`, with provenance SHA-256
`5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.
Its embedded dark ground remains unchanged unless the founder supplies
separate light artwork. Four clear animated cards open Formation, Autolaunch,
Techtree, and Regents Labs. Their motion follows the same cancellable,
reduced-motion-safe Anime.js vocabulary as the application shell, while the
complete hero remains readable and usable without JavaScript.

## Formation

**AP-100 — One lifecycle.** Formation is one `/formation` lifecycle with three
local panels: Overview, Cloud, and Hermes Skills. They are not
separate product route families.

**AP-101 — Founder outcome.** A person forms and manages one Regent identity
and its Hermes capabilities in one guided experience. When the customer
enrolls in Regent-hosted Cloud, that Hermes agent runs on a Sprite with its
runtime status visible alongside its profiles and skills.

**AP-101A — Formation capability boundary.** Formation Core owns Regent
identity and Hermes management for any supported Hermes runtime. Regent Cloud
is the separate paid managed service and runs only on a Regent-hosted Sprite.
Do not make Formation Core or a customer's independently operated Hermes
runtime depend on Sprite enrollment or Regent-funded infrastructure.

**AP-102 — Practical prepaid.** The customer adds prepaid Stripe balance.
Sprite runtime and hosted AI gateway usage draw from that same customer-funded
credit. One account may own one or more Sprites under this single credit
authority, but at most one Regent-hosted Sprite may be active for that account
at a time. Every active run uses a five-minute renewable Sprite Task/run lease,
refreshed once per minute only while the account remains eligible and a valid
prepaid reservation covers the run. The 30-minute Oban job is billing
reconciliation and settlement, not the sole safety control and not a provider
billing cutoff.

When available prepaid credit falls below the `$1` reserve trigger, or when
the authorization lease cannot be renewed, Regent blocks every new start,
wake, customer-paid AI request, and task renewal; stops the Hermes service;
kills active exec sessions; and deletes the Task hold. The `$1` threshold is a
reserve trigger, not a claim that maximum loss is one dollar. Those
acknowledgements reduce continuing activity but do not prove that compute
billing has stopped.

The honest pause states are `pause_needed`, `pause_requested`,
`pause_confirmed`, and `exposure_unresolved`. `exposure_unresolved` blocks all
new starts, wakes, task renewals, and AI work while operators reconcile. Every
paid AI request has its own reservation; work already started may consume only
that reservation. Any operational incident must reach a resolved state or
`exposure_unresolved` within ten minutes. Small exceptional
provider/control-plane exposure is acceptable only when it is visible,
monitored, alerted, durably evidenced, and reconciled.

The provider documentation exposes no force-pause or stop-Sprite operation.
Task expiry or deletion releases the hold, after which a Sprite may pause after
an idle window of about 30 seconds; an active exec or console, open TCP
connection, or service traffic can keep it awake. Service-stop and exec-kill
responses acknowledge processes, not billing cutoff. The documented warm
pause stops compute billing while persistent storage remains billable and
intact. The provider does not document a durable billing-stopped receipt, a
maximum pause SLA, a usage-freshness or cost API, or a fixed published RAM
ceiling.

The binding operational incident ceiling is ten minutes. `pause_confirmed`
means Regent has observed runtime quiescence; it is not a provider billing
receipt. Do not infer it from process or Task acknowledgements alone, and do
not claim a maximum provider-side loss that current documentation cannot
prove. `exposure_unresolved` remains blocked and operator-visible until
reconciled.

Official basis: [Keeping a Sprite Running](https://docs.sprites.dev/keeping-sprites-running/),
[Lifecycle and Persistence](https://docs.sprites.dev/concepts/lifecycle/),
[Working with Sprites](https://docs.sprites.dev/working-with-sprites/),
[Services](https://docs.sprites.dev/concepts/services/), and the
[Sprites API reference](https://docs.sprites.dev/api/v001-rc30/).

Top-up, refund, spend limits, and automatic recharge belong to this one credit
owner; they must never create a second shadow balance.

**AP-103 — Preserved chat.** Hermes chat/execution and ChatGPT provider/account
integration remain. They are not part of the removed public/private messaging
system.

**AP-104 — Customer-paid AI origin.** All Regent-funded customer AI work
originates through that customer's enrolled Sprite/Hermes lifecycle. Every
paid AI request has its own prepaid reservation; web and server features may
not create a separate paid-AI path. New work and lease renewal require a valid
account and reservation; already-started work uses only its own reservation.
Nous Hermes Cloud and local Hermes devices may use Regents CLI, but they are
not Regent-funded Sprite runtime unless the customer explicitly enrolls them
in Regent Cloud.

## Autolaunch

**AP-110 — Overview.** `/autolaunch` is an overview of recently created and
featured auctions, top tokens, and recently graduated tokens. It links into
the canonical auction, token, and create routes.

**AP-111 — Complete web path.** Autolaunch should eventually be usable
entirely through the web. The CLI and agents remain first-class, but the web
must not require a CLI escape hatch for the approved human journey.

The minimum complete journey is: create a launch with required and optional
reputation details; review and begin its auction; browse active and completed
auctions; place and manage wallet-signed bids; reclaim bids when an auction
does not graduate; finalize/claim the supported result; browse graduated
tokens; and use wallet-signed token-market actions when their canonical
contracts are admitted. A human may complete this through the web, while an
agent may prepare and operate the corresponding non-custodial path through the
CLI. Pairing grants visibility and coordination only, never signing power.

**AP-112 — Reputation signal.** Profile and Autolaunch Create use one
canonical set of optional verified connections: X, GitHub, Farcaster, ENS,
and World. The UI recommends connecting all five for stronger Autolaunch social signal,
but none is required for account authentication. Public output shows verified
connections only.

**AP-113 — Wallet authority.** Bids, exits, returns, claims, swaps, and other
money actions are prepared and reconciled by the app but signed by the
initiating wallet. Pairing or profile linkage never grants signing power.

**AP-114 — Founder acceptance on Base.** Autolaunch founder acceptance includes
selected real Base transactions from a bounded, independently reviewed action
manifest. The browser-connected user wallet signs every value action. The
server may prepare, register, verify, and reconcile those actions, but it never
moves the customer's money.

## Techtree

**AP-120 — Participation model.** Web Techtree is initially read-only for node
creation. Humans browse, run local notebooks, comment, and use approved human
reactions. Agents create and publish nodes through Regents CLI. The initial
web and CLI have no paid payloads.

The retained agent capabilities are: attach and publish nodes; run benchmark
and evaluation work; optimize and measure skills through receipt-backed
SkillOpt runs; create and review Question Forge candidates; and conduct
notebook-centered research with reproducible provenance. These are founder
outcomes, not commitments to copy the old resources, command names, or run
stores. The greenfield implementation may choose simpler Ash models and CLI
verbs while keeping the capability legible and verifiable.

**AP-121 — Overview.** `/techtree` explains what Techtree is, how humans
participate, how an agent participates through verified CLI commands, and
links the five tree roots.

**AP-122 — Five roots.** The contextual navigation lists exactly these roots,
in this order:

1. GeneBench-Pro Reference Lab
2. Question Forge Metaskills
3. New Question Candidates
4. BixBench Capsule Lab
5. Skill Training Lab

Any tree may contain arbitrary reference/data nodes. The roughly 250-node BBH
Training Corpus belongs under BixBench Capsule Lab unless later approved
domain modeling places it elsewhere; it is not a sixth root.

**AP-123 — Map and List.** Map and List are interchangeable presentations of
one `/techtree/:tree_slug?view=map|list` route. Map is the default underlying
view. A bottom `List` tab raises the full-screen List panel; a top `Map` tab
lowers it. This is the approved vertical panel transition.

Clicking a tree name preserves the active Map/List mode. First Techtree tree
visit defaults to Map. Each tree row exposes separate Map and List selectors
that open the target tree while explicitly choosing the mode. Direct loads,
refreshes, and deep links render the requested view immediately. Same-tree
Map/List controls replace the current history entry and preserve scroll;
cross-tree navigation carries the chosen/current view, creates genuine
navigation, and starts at the top. Hover may reveal the icons on pointer
devices, but equivalent controls must be available to keyboard and touch
users. The old local-only behavior and any dual route/query interpretation are
retired.

**AP-124 — Node detail.** Map and List both open
`/techtree/nodes/:node_id`. Node detail supports local-compute Marimo notebook
runs through WASM. Web has no Publish item.

**AP-125 — Founder notebook corpus.** Local founder acceptance includes one
example Marimo notebook for each of the five Techtree roots, plus the ten
GeneBench-Pro examples reworked as Marimo notebooks. The full BBH corpus is a
later batch-validation scope, not part of this first interactive acceptance
gate.

## Regent Ops, Privy, staking, and redeem

**AP-130 — Regents Labs root.** `/app` is a small Regent Ops overview: active
identity, wallet, REGENT/USDC balances, staking/rewards summary, and direct
paths to Stake, Redeem, and Profile. It is not a port of the old dashboard.
`Regent Ops` describes the capability area; the visible app name is always
`Regents Labs`.

The signed-in Profile destination is the account's one canonical public Regent
record at `/regents/:slug`. Until that Regent and slug exist, the shell shows
the account identity and Sign Out but does not invent or expose a Profile link.

**AP-131 — Privy close port.** Preserve the verified old-platform
browser-human behavior closely: a verified Privy access token plus CSRF creates
or renews the signed local session; logout invalidates it; anonymous viewing
stays anonymous; browser-posted provider ids, wallets, roles, and profile fields
are never trusted. The session contains the canonical local human id, not a
second identity graph. SIWA agents use a separate rail.

**AP-131A — Existing HumanAccount owner.** The Ash `HumanAccount` resource maps
the protected existing `platform.platform_human_users` table directly. It does
not create, copy, import, or migrate a second human-account store. Migration
generation is disabled for this existing-table resource. Sign-in may persist
only identity and wallet evidence returned by successful server-side Privy
verification; profile display changes use separate owner-authorized actions.

**AP-131B — First-click sign-in performance.** Anonymous page load keeps Privy
and wallet-provider code out of the initial application bundle. The first Sign
In action displays pending feedback within 100 ms and may fetch at most 1 MiB
of new gzip-compressed JavaScript before the provider interface is usable. The
target is provider readiness within 2.5 seconds on Fast 4G. A failed load shows
an action-specific, retryable customer message. Solana, Farcaster, Stripe, and
chain-specific adapters load only when the selected identity or wallet action
actually needs them; hiding a multi-megabyte payload behind lazy loading does
not satisfy this rule.

**AP-132 — Staking close port.** Preserve the working Base staking experience:
public overview, wallet account state, positions, balances, pending rewards,
stake, unstake, claim USDC, claim REGENT, and manual claim-and-restake. There
is no automatic restaking. Address and ABI truth come from canonical
configuration/contracts. Every prepared transaction binds chain, target,
calldata, signer, expiry, and action identity; success requires a successful
receipt and an onchain re-read.

**AP-133 — Redeem close port.** `/redeem` initially supports only the working
onchain Animata I/II NFT-to-REGENT flow: eligibility, NFT approval, exact USDC
approval, redeem, and claim. Stripe-credit redemption is not admitted. A
submitted or reverted transaction is not success; receipt confirmation and
reconciliation are mandatory.

Automated tests and local demonstrations must not move live value. Any manual
end-to-end money test proceeds only through explicit user wallet review and
signature.

## Profiles and public identity

**AP-140 — Display identity.** Public display resolution is:

1. the profile-selected identity;
2. the user’s `<name>.regent.eth` nameclaim;
3. the user’s ENS name; or
4. a shortened wallet such as `0x…a1b2`.

The canonical signed identity remains private and is never replaced by a
display label.

**AP-141 — Public Regent profile.** The public record may show the selected
name/avatar/description, verified wallet, coarse public Formation/Hermes
status, linked Autolaunch auction/token, Techtree nodes, useful public
comments/reactions, and the optional verified reputation connections. It does
not expose private runtime health, billing details, secrets, chat, or signing
internals.

## Comments, reactions, and messaging hard cut

**AP-150 — Remove messaging, preserve tools.** Remove the ideated public and
private XMTP/GossipSub messaging system: rooms, DMs, presence, unread state,
global chat destinations, and shared chat drawers. Preserve ChatGPT
integration and Hermes chat/execution.

This is a complete hard cut, not just a hidden navigation change. Active
product messaging code, database schema, routes/controllers, contracts,
generated clients, CLI commands/runtime state, packages, docs, and metadocs
must all be removed. A historical record may retain messaging text only when
it is explicitly marked as superseded evidence and cannot guide current work.

**AP-151 — Record-attached comments.** Techtree nodes, Autolaunch auctions,
and Autolaunch tokens may have one flat comment board per record. Comments are
newest-first, update in real time, and never become rooms, threads, replies,
DMs, presence, or unread state. Techtree's approved human reactions attach to
individual comments; they do not turn the board into ranked or threaded chat.
Real-time inserts do not move a reader who is looking at older comments; the
UI surfaces new activity locally.

Public records have publicly readable comments. Restricted/unpublished
records inherit their target’s visibility. Posting is permitted for a signed-
in browser human or SIWA-authenticated CLI agent through distinct transports
that construct the same principal-aware Ash action.

**AP-152 — Comment content.** A comment is immutable and limited to 2,000
user-perceived Unicode characters (grapheme clusters), counted after the
canonical newline/normalization rules. Use MDEx with a restricted Markdown
vocabulary: paragraphs, safe links, emphasis, inline/fenced code, and lists.
Disallow raw HTML, images, embeds, scripts, headings, and tables.

The author may delete their comment. Configured Regent admin wallet addresses
may delete any comment. Public output removes it completely with no tombstone;
a private audit retains deletion time, deleting identity, and whether the
authority was author or admin. There is no edit or restore action.

**AP-153 — Autolaunch recency.** Autolaunch comments have no reaction or score
ordering. Recency is the only order.

**AP-154 — Techtree reactions.** Human web accounts may react to an individual
Techtree comment with `Useful`, `Off-topic`, or `Negative`. Each human has
at most one current reaction per comment and may change or remove it. These
reactions never reorder the newest-first board.

SIWA agents do not use the human comment-reaction controls. They attach one
evidence reaction to a stable Techtree node address only after Regent has
durable, verified client-delivery evidence for the full node payload. A mere
entitlement, request, or partial response is insufficient. The exact agent
vocabulary is:

- `evidence_verified` — **Evidence checks out**: the supplied data, proof, and
  reasoning were reviewed and found consistent;
- `result_reproduced` — **Result reproduced**: the method was independently
  rerun and produced the claimed result;
- `useful` — **Useful**;
- `needs_evidence` — **Needs evidence**;
- `contradicted` — **Contradicted**; and
- `not_reproducible` — **Could not reproduce**.

An agent has one current reaction per stable node address and verified agent
identity, and may create, change, or remove it. The record stores the reaction
timestamp and exact payload hash reviewed. It survives later payload-hash
changes, remains publicly countable as historical provenance, and never
pretends it covers the newer bytes. Node-evidence reactions and human comment
reactions are separate records and separate contracts.

## Comparing intermediate results

Use the requirement ids in this document when reviewing screenshots, route
artifacts, code, and tests. An intermediate result is aligned only when:

- its admitted route or capability is named here or separately approved;
- it preserves the four protected datasets and the identity/money rules;
- the visible behavior matches the relevant app and shell directives;
- its source owner and generated artifacts converge mechanically;
- real browser or contract evidence covers the claim being made; and
- incomplete capability status is labeled honestly rather than hidden behind
  polished placeholder UI.

The first local milestone is proven only when a person can run `ash-platform`
locally, use the canonical shell routes, sign in and out with Privy, inspect
staking/redemption state, and exercise the protected preparation/confirmation
flows without automated live value movement. Narrow scaffold tests alone do
not prove that milestone.

This document remains the durable product-intent hub and must not be turned
into a progress checklist. Execution tickets, implementation specs, and review
artifacts may be consolidated or deleted after the app is stable without
changing these directives.
