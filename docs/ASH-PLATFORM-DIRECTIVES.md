# ash-platform directives

This is the single human-readable statement of what `ash-platform` is meant to
be. It consolidates the founder directives and the decisions made during the
greenfield and interface grilling sessions through 2026-07-10.

It describes product intent and acceptance principles, not implementation
status. Beads owns work status. Source contracts own exact public interfaces.
The implementation may improve as we learn, but it must not quietly change a
founder directive.

## Authority and interpretation

`founder.md` remains the stack constitution. This document is its
`ash-platform` product supplement and records newer, more specific founder
decisions for the greenfield application.

Old tickets, specs, screenshots, handoffs, and code are historical evidence.
They are not requirements merely because they already exist. Functionality is
admitted to `ash-platform` only after the founder and Chief explicitly accept
the capability. When an old record conflicts with a newer directive here, the
newer directive wins.

The sacred invariants are deliberately small:

- Preserve the four protected datasets named below.
- Preserve the core founder capabilities: what humans and agents must be able
  to accomplish across Formation, Autolaunch, Techtree, and Regent Ops.
- Preserve identity, money, and signing safety.
- Preserve especially strong product ideas, but allow the route, UI, domain,
  and implementation shape to improve.

Everything else may be rewritten or deleted when a simpler, more correct
greenfield design earns its place.

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

No production database connection is allowed until each table has an explicit
relationship, actor, authorization, and migration/import plan. The initial
shell does not connect to them.

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

**AP-031 — Techtree precedence.** `/techtree/nodes/:node_id` wins before the
dynamic tree route. `nodes` is reserved and invalid as a tree slug.

**AP-032 — No hidden route families.** Formation panels and Techtree Map/List
are local presentation state, not duplicate route families. Docs and other
old routes are not implicitly admitted.

## Persistent shell

**AP-040 — App selector.** The upper-left control is one visually obvious,
one-line selector: canonical crown, current app label, and chevron. The four
labels are Formation, Autolaunch, Techtree, and Regents Labs. Selecting one
always opens its canonical root; there is no per-app last-route memory.

**AP-041 — Account control.** The upper-right target is separate from the app
selector. It shows `Sign In` while logged out. While signed in, it shows the
resolved profile/ENS/wallet label and opens the profile menu. There is no
“Public workspace” label and no combined app/account disclosure.

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

- Formation: Overview, Cloud, Hermes Skills, Billing.
- Autolaunch: Auctions, Tokens, Create.
- Techtree: the five named seed trees in the order recorded below. Each row
  exposes Map and List selectors.
- Regents Labs: Overview, Stake, Redeem, Profile.

**AP-045 — One scroller.** The shell has one internal content scroller. Header
and desktop sidebar remain fixed. Every route, app-root navigation, Back, and
Forward starts at the top; prior route scroll offsets are not restored. Local
tabs/filters preserve position only while it remains valid. Async content,
status changes, and real-time inserts never force-scroll the reader.

**AP-046 — Failure isolation.** The shell stays visible and interactive while
destination content loads, is empty, or fails. Only the destination region
shows loading/error/retry state. App selector, account, theme, and unaffected
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

Anime.js is the approved motion library. Use the current stable release and
the installed Regent Anime.js skill for lifecycle, interruption, cleanup, and
LiveView-hook behavior.

## Theme, material, and voxel language

**AP-060 — Theme.** The profile menu offers exactly System, Light, and Dark.
The choice persists locally. System follows later operating-system changes.
Theme changes use only a 140–180 ms color/background crossfade, with no travel,
scale, blur animation, or layout shift. Reduced motion changes immediately.

**AP-061 — Structural material.** All four apps share one high-opacity
liquid-glass material system: neutral gradient fills, restrained gradient
strokes, consistent elevation, and readable contrast over the SVG grid. The
stroke is an edge treatment, not a glow. Product identity comes from the
background, accent, selected state, mark, and content—not four panel recipes.

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

Voxel palettes use the active app accent plus neutrals. Techtree may use a
restrained biological green secondary. Do not use a cross-product rainbow or
decorative status colors.

**AP-064 — Background assets.** The founder will supply separate light/dark
SVG cutting-mat backgrounds for each app. The ground remains neutral/shared;
the following values are guide/grid colors, not full background fills:

| App | Light guide RGB | Dark guide RGB |
| --- | --- | --- |
| Home / Regents Labs | `rgb(0, 95, 146)` | `rgb(75, 168, 224)` |
| Formation | `rgb(176, 63, 0)` | `rgb(230, 115, 57)` |
| Autolaunch | `rgb(0, 122, 58)` | `rgb(65, 214, 134)` |
| Techtree | `rgb(26, 88, 143)` | `rgb(109, 169, 231)` |

Preserve the cutting-mat opacity rhythm: faint fine grid, stronger medium
grid, and controlled primary guides. Do not silently tint the neutral ground.

**AP-065 — Homepage hero.** The approved dark hero input is
`/Users/sean/Downloads/hero-bg-dark.svg`, SHA-256
`5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.
It is copied into `ash-platform` only through the Design-owned asset slot. Its
embedded dark ground remains unchanged unless the founder supplies separate
light artwork.

## Formation

**AP-100 — One lifecycle.** Formation is one `/formation` lifecycle with four
local panels: Overview, Cloud, Hermes Skills, and Billing. They are not
separate product route families.

**AP-101 — Founder outcome.** A person forms and manages one cloud Regent: a
Hermes agent running on a Sprite, with its profiles, skills, runtime status,
and billing visible in one guided experience.

**AP-102 — Practical prepaid.** The customer adds prepaid Stripe balance.
Sprite runtime and hosted AI gateway usage draw from that same customer-funded
credit. Regent reserves ahead of use and pauses near zero. Small exceptional
provider/control-plane exposure during an outage is acceptable only when it is
visible, monitored, alerted, durably evidenced, and reconciled.

At insufficient credit, pause the Sprite, reject new AI jobs, and allow work
already started to finish only within credit already reserved for it. Because
Hermes jobs run on the Sprite, pausing the Sprite pauses further AI use.

Top-up, refund, spend limits, and automatic recharge belong to this one credit
owner; they must never create a second shadow balance.

**AP-103 — Preserved chat.** Hermes chat/execution and ChatGPT provider/account
integration remain. They are not part of the removed public/private messaging
system.

## Autolaunch

**AP-110 — Overview.** `/autolaunch` is an overview of recently created and
featured auctions, top tokens, and recently graduated tokens. It links into
the canonical auction, token, and create routes.

**AP-111 — Complete web path.** Autolaunch should eventually be usable
entirely through the web. The CLI and agents remain first-class, but the web
must not require a CLI escape hatch for the approved human journey.

**AP-112 — Reputation signal.** Profile and Autolaunch Create use one
canonical set of optional verified connections: X, Farcaster, ENS, and World.
The UI recommends connecting all four for stronger Autolaunch social signal,
but none is required for account authentication. Public output shows verified
connections only.

**AP-113 — Wallet authority.** Bids, exits, returns, claims, swaps, and other
money actions are prepared and reconciled by the app but signed by the
initiating wallet. Pairing or profile linkage never grants signing power.

## Techtree

**AP-120 — Participation model.** Web Techtree is initially read-only for node
creation. Humans browse, run local notebooks, comment, and use approved human
reactions. Agents create and publish nodes through Regents CLI. The initial
web and CLI have no paid payloads.

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
one `/techtree/:tree_slug` route. Map is the underlying view. A bottom `List`
tab raises the full-screen List panel; a top `Map` tab lowers it. This is the
approved vertical local transition.

Clicking a tree name preserves the active Map/List mode. First Techtree tree
visit defaults to Map. Each tree row exposes separate Map and List selectors
that open the same route while explicitly choosing the initial mode. Hover may
reveal the icons on pointer devices, but equivalent controls must be available
to keyboard and touch users.

**AP-124 — Node detail.** Map and List both open
`/techtree/nodes/:node_id`. Node detail supports local-compute Marimo notebook
runs through WASM. Web has no Publish item.

## Regent Ops, Privy, staking, and redeem

**AP-130 — Regents Labs root.** `/app` is a small Regent Ops overview: active
identity, wallet, REGENT/USDC balances, staking/rewards summary, and direct
paths to Stake, Redeem, and Profile. It is not a port of the old dashboard.

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

**AP-151 — Record-attached comments.** Techtree nodes, Autolaunch auctions,
and Autolaunch tokens may have one flat comment board per record. Comments are
newest-first, update in real time, and never become rooms, threads, replies,
DMs, reactions, presence, or unread state. Real-time inserts do not move a
reader who is looking at older comments; the UI surfaces new activity locally.

Public records have publicly readable comments. Restricted/unpublished
records inherit their target’s visibility. Posting is permitted for a signed-
in browser human or SIWA-authenticated CLI agent through distinct transports
that construct the same principal-aware Ash action.

**AP-152 — Comment content.** A comment is immutable and limited to 2,000
Unicode characters. Use MDEx with a restricted Markdown vocabulary:
paragraphs, safe links, emphasis, inline/fenced code, and lists. Disallow raw
HTML, images, embeds, scripts, headings, and tables.

The author may delete their comment. Configured Regent admin wallet addresses
may delete any comment. Public output removes it completely with no tombstone;
a private audit retains deletion time, deleting identity, and whether the
authority was author or admin. There is no edit or restore action.

**AP-153 — Autolaunch recency.** Autolaunch comments have no reaction or score
ordering. Recency is the only order.

**AP-154 — Techtree reactions.** Human web accounts may react to a node with
Useful, Off-topic, or Negative. Agent reactions use a richer evidence
vocabulary and are allowed only after the agent has downloaded the full node
data. The vocabulary must clearly distinguish reproduction from independent
verification.

An agent has one current reaction per stable node address and agent identity.
The reaction stores a timestamp and the payload hash actually reviewed. It
survives later node-hash changes as provenance; display must not pretend the
stored hash reviewed newer bytes. Reactions do not reorder the newest-first
comment board.

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

Execution state and closure evidence live in Beads epic `regent-2mf0` and its
children. The current route/source contract and Design handoff live under
`docs/specs/founder-shell/`. This document remains the product-intent hub and
must not be turned into a progress checklist.
