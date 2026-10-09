# Changelog

This file is append-only. Add new dated entries at the end, in chronological order.
Do not edit, reorder, or remove existing entries; append corrections separately.
Release contents and verified deployment records are recorded separately.

## 2026-09-18 — Regents production release contents

### Staking and shared metadata

- Move the circulating market-cap figure into the right-hand staking summary,
  directly below Circulating REGENT, labeled **CIRCULATING MCAP:**.
- Remove the old market-cap box beside Buy REGENT and View Chart. Preserve both
  links, the existing calculation, the unavailable-value dash, and matching loading rows.
- Render public discovery metadata through the shared `Regent.AgentMetadata`
  component, pinned to design-system revision
  `36eb9d18d1e59df019fae0944183f8d6827bd7fe`.

### Included from the existing main branch

- `97761e4`: Align shell/overview/staking browser checks and correct phone overflow
  after the design refresh.
- `b142e4f`: Align homepage browser checks with the dark-locked landing page.
- `1fc85ef`: Let the page grid own the Redeem collection layout.
- `e00d4dd`: Give the Autolaunch Create treasury form room on a phone.
- `8ad33b9`: Clean up only the private drafts saved by each browser verification.

### Retained from the deployed agent-readiness release

- Public Markdown negotiation and recoverable agent-facing errors.
- Documentation, About and Contact pages; discovery metadata and sitemap.
- Updated agent guidance, public API documentation and synchronized contract headers.

This release targets Regents only. It adds no database migrations, changes no
claim ownership or Privy mappings, and does not deploy the other product sites.


## 2026-09-18 — Production deployment verified

- Deployed application revision: `58237fe091a8643529ee83cdf7e7c08b7aaddc6d`.
- Image digest: `sha256:b6ef5320accef09f57e9cc0c3b6b12d8d7b689133624afa6eb61728597ef36a1`.
- Shared UI revision: `36eb9d18d1e59df019fae0944183f8d6827bd7fe`.
- Verified the running production image and single healthy web instance.
- Verified public pages, Markdown negotiation, discovery metadata, styles and icons;
  Stake, Redeem and Overview connect successfully on desktop and mobile.
- Confirmed the Circulating MCAP row is below Circulating REGENT with no old left-hand box.
- Before/after claim, account, ownership/Privy mapping, allowance and credit fingerprints
  are identical. No new database migrations were included.
- Existing dependency advisory remains: Ash 3.33.0, medium-severity CVE-2026-86338
  (field-policy calculation/aggregate information disclosure). Dependencies were not
  changed by this release; remediation remains a separate follow-up.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.


## 2026-09-18 — Maintenance release contents (prepared, not yet deployed)

### Security

- Update Ash from 3.33.0 to 3.33.6, which includes the 3.33.4 fix for
  medium-severity CVE-2026-86338. Regents declares no field policies, so this
  closes the advisory rather than a live exposure. Spark, Reactor, Multigraph,
  Sourceror and Spitfire move with it. No application code changed for this update.

### Shared libraries

- Accept negotiation, `Vary` merging, public-document Markdown and the Markdown and
  JSON error bodies now come from the shared `regent_agent_access` package, pinned to
  elixir-utils revision `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`. The public
  document list, routes and the HTML error page stay in Regents. Responses were
  compared with the previous build across 95 request cases and are unchanged.
- Shared UI moves to design-system main `0818c4af559947ebbe6bd5f1d92264941efa6342`,
  which contains the deployed agent-metadata revision
  `36eb9d18d1e59df019fae0944183f8d6827bd7fe` and adds the inert gray fill for
  disabled primary buttons.
- Release packaging lists the new shared package.

This release targets Regents only. It adds no database migrations, changes no
claim ownership or Privy mappings, and does not deploy the other product sites.


## 2026-09-18 — Maintenance release deployment verified

- Deployed application revision: `14e32733821c9fdea0c142753d030463f8f5982c`.
- Image digest: `sha256:528a67f84ff12f0804260d817904202c5160a85168678fd2e1a0165cf193465a`.
- Shared UI revision: `0818c4af559947ebbe6bd5f1d92264941efa6342`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels and the single
  healthy web instance.
- Verified 95 request cases against the live site: status, content type and `Vary`
  match the prepared build in every case, including Markdown negotiation, refusals
  and the Markdown and JSON not-found bodies.
- Stake, Redeem and Overview connect on desktop and phone width with no sideways
  scrolling and no browser errors; the seven-day USDC figure reads 0.00 USDC.
- Before/after claim, account, ownership/Privy mapping, allowance and credit
  fingerprints are identical. No database migrations were included.
- `mix hex.audit` reports no advisories; CVE-2026-86338 is closed.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.


## 2026-09-18 — Correction to the maintenance release verification

- The line above saying `mix hex.audit` reports no advisories is wrong. The Ash
  advisory CVE-2026-86338 is closed, but the audit lists one other advisory:
  Igniter 0.8.2, low-severity CVE-2026-82584 (the `mix igniter.install`
  confirmation prompt can be fed terminal control characters by package metadata).
- Igniter is a development and test tool only. It is not part of the production
  image, so the deployed site is not affected. The fix is in Igniter 0.8.4 and
  remains a separate follow-up.


## 2026-09-18 — Polish release contents

### Interface

- The $REGENT copy row shows its green check only after a copy. The "CA copied"
  note sits inside the row beside the check and clears after a moment.
- The signed-in menu's first row reads **Account**, in the accent colour, with an
  icon, on one line.
- On Stake, the Stake or Unstake button takes its lit look while a valid amount
  stands in the field. This is appearance only; every press reaches the wallet.

### Maintenance

- Update Igniter, a development-only tool, from 0.8.2 to 0.8.4, closing
  low-severity CVE-2026-82584. The dependency audit reports no advisories.
- The CLI plugin install tests match the current behaviour: automatic install
  covers only the runtimes found on the machine.

Shared library and shared UI revisions are unchanged from the maintenance release.
This release targets Regents only. It adds no database migrations, changes no
claim ownership or Privy mappings, and does not deploy the other product sites.


## 2026-09-18 — Polish release deployment verified

- Deployed application revision: `8c8b77f58d1f2a73e50937178fc817db1f6ed638`.
- Image digest: `sha256:0edfb052b3b481b392ac3d4226b94f3616d392a6717cc022e77737a304ba6c98`.
- Shared UI revision: `0818c4af559947ebbe6bd5f1d92264941efa6342`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels and the single
  healthy web instance.
- The 95 live request cases match the previous release on status, content type and
  `Vary`, and every non-page body is byte-identical.
- On the live site the $REGENT copy row shows no check before a copy, shows the
  check and "CA copied" inside the row after one, and clears. Stake, Redeem and
  the homepage connect on desktop and phone width with no sideways scrolling and
  no browser errors. The Account row and the lit stake button appear only when
  signed in and were checked by style, not in a signed-in session.
- Before/after claim, account, ownership/Privy mapping, allowance and credit
  fingerprints are identical. No database migrations were included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.


## 2026-09-18 — Autolaunch leaves Regents: release contents

Founder decision: autolaunch.sh is the product, so Regents no longer carries its
own copy of it.

### Removed

- The in-app Autolaunch pages (`/autolaunch` and everything under it) and the
  `/api/autolaunch/v1/*` endpoints. They were closed in production; they now
  answer "not found". The homepage, Overview and Stake still name Autolaunch and
  link to autolaunch.sh.
- The background reader of Autolaunch events on Base, the Autolaunch contract
  interfaces kept for those pages, and the separate Autolaunch on/off setting.
- Comments, which only Autolaunch records used: the comment panel, its moderation
  setting, formula typesetting and the library behind it.
- The published API description and route list no longer mention any of the above.

### Maintenance

- Six tests that still described older pages now match what is released: the
  error body for API callers, the homepage's public links, the pages that stay
  open while the app is closed, and the market cap position on Stake.

This release targets Regents only. It adds no database migrations and changes no
data: the Autolaunch tables belong to the Autolaunch site and were never managed
from here, and the empty Regents comments table is left in place. It changes no
claim ownership or Privy mappings and does not deploy the other product sites.
Shared library and shared UI revisions are unchanged.

## 2026-09-18 — Autolaunch leaves Regents: deployment verified

- Deployed application revision: `64ed153e369cd10fe107c3951eacaa41c4e76400`.
- Image digest: `sha256:b3136df92999172082fc66236ebf9a3d92776920a1e88963e2605bcdd1048ada`.
- Shared UI revision: `0818c4af559947ebbe6bd5f1d92264941efa6342`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image and the single healthy web instance.
- The 95 live request cases match the previous release on status, content type and
  `Vary`, except the five `/api/autolaunch/v1/auctions` cases, which now answer
  "not found" as intended. `/autolaunch` answers "not found"; the public API
  description, the sitemap and the agent guide carry no Autolaunch addresses.
- On the live site the app side navigation shows Overview, Stake and Redeem, the
  links to autolaunch.sh, techtree.sh and patchbay.help remain, and Stake loads at
  desktop and phone width with no sideways scrolling and no browser errors.
- Before/after claim, account, ownership/Privy mapping, allowance and credit
  fingerprints are identical. No database migrations were included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-18 — App shell cleanup after the Autolaunch removal

- Removed the header search box and its phone-menu twin. Only Autolaunch pages ever
  showed it, so no page could reach it any more.
- Removed the placeholder page loader that stood in for unbuilt pages. Every page in
  the app now has its own real content, and the Regent profile page no longer waits
  on a placeholder before showing.
- The route handoff for design no longer carries a search setting or a page loading
  state. Header spacing is unchanged.
- No database, sign-in, wallet or public address changes.

## 2026-09-18 — Browser test upkeep and a correction

- Correction to the Autolaunch removal notes: the Stake, Redeem and Regents Club
  browser tests were never out of date. They failed only because they were run on a
  different local port than the one the test wallet is tied to. On the intended port
  the whole browser suite passes except one showcase database check, which needs a
  specially named per-run local database.
- The homepage card hover test now looks at the card heading the page really uses.
- New browser test: after signing out on Stake, the stake button asks for the
  sign-in again and nothing is sent to the wallet.

## 2026-09-18 — Fix: a worn-out sign-in no longer locks a browser out of the app

- Problem: a browser still holding a sign-in the site no longer accepts (signed
  out elsewhere, replaced by a newer sign-in that never reached that browser, or
  saved in a shape the site no longer reads) was sent from Stake, Redeem, Overview
  and every other app page back to the homepage, every time. Only deleting the
  site cookie by hand let that person back in. This was present before today's
  releases; none of them changed it.
- Fix: the page now notices it was opened with a worn-out sign-in and clears it
  in the background, through the same sign-in checks that already guard the
  cookie. The person stays on the page they asked for, as a guest, and can sign
  in again normally. Ordinary page loads still never rewrite the sign-in cookie.
- No database, wallet or public address changes.

## 2026-09-18 — Lockout fix release contents

- Includes the two entries above: the app shell cleanup and the fix for a worn-out
  sign-in locking a browser out of the app. After the worn-out sign-in is cleared
  the page refreshes itself once and stays where the person asked to be.
- New browser test: a browser still holding a signed-out or replaced sign-in opens
  Stake and Redeem normally. The test fails without the fix.
- The live site now logs requests and outcomes only. Database queries and debug
  detail no longer appear in the live logs.

Shared library and shared UI revisions are unchanged. This release targets Regents
only. It adds no database migrations, changes no claim ownership or Privy mappings,
and does not deploy the other product sites.

## 2026-09-18 — Lockout fix deployment verified

- Deployed application revision: `eb741cf2412b8c83515d5e6d610419ae33c5a8b5`.
- Image digest: `sha256:6e82a7eb1935cad0bbedc0c2d75bec7a906b789fd858ec0acd38359350931b9e`.
- Shared UI revision: `0818c4af559947ebbe6bd5f1d92264941efa6342`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels and the single
  healthy web instance.
- The 95 live request cases match the previous release on status, content type and
  `Vary`, and every non-page body is byte-identical.
- Stake and Redeem connect on desktop and phone width with no sideways scrolling
  and no browser errors. The live logs no longer carry database queries.
- Before/after claim, account, ownership/Privy mapping, allowance and credit
  fingerprints are identical. No database migrations were included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Account page and shared holographic card

### Account page

- `/account` replaces the old `/profile` page. It lives inside the app shell
  (side navigation, header, theme) and is drawn from the sign-in the site already
  holds, so a signed-in person is never asked to sign in again to see it.
- Shows: the picture and name the header uses, on a pointer-lit identity card;
  the signed-in wallet with a Copy button; other linked wallets; ENS name;
  display name; World ID verification; the names those wallets hold (read
  directly, first 50, with an honest "couldn't be read right now" when the
  record is unavailable); verified connections (X, GitHub, Farcaster); and a
  Sign out button. A guest sees a sign-in panel on the same page instead of
  being bounced home.
- The account menu's Account row now opens `/account`. The dormant Settings route
  and its page are retired; the old profile page's browser client and its
  Connect X / historical-names loader are removed.
- `/api/v1/profile` (the shared profile API the other sites use) and
  `/api/v1/claims` (the published agent API) are unchanged.
- Signed-in people may read their own historical names with the wallets their
  sign-in verified; fresh Privy proof still works for the API.

### Shared holographic card

- New design-system component `Regent.HolographicCard.card`: a graphite foil card
  that tilts and lights under the pointer, drawn with the same graphics library
  as the homepage crown. Still and flat for reduced motion, forced colours and
  browsers without WebGPU. Recorded as the founder-approved exception to the
  flat-panel rule.
- Design-system revision to be pinned at release; the foil material's attribution
  is recorded in the design system's third-party notices and referenced here.

## 2026-09-19 — Account page deployment verified

- Deployed application revision: `e518f16609799c6053764893c2c8c49bf93d71ae`.
- Image digest: `sha256:5dec0af084fd9880841fe910bfa3dfa9ac70ac642ee073510ff6d5c96d66a22e`.
- Shared UI revision: `6dde98f219fac4fa8972ca67710b57a5c4e27a3f` (holographic card).
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels and the single
  healthy web instance.
- `/account` answers inside the app shell with the sign-in panel for guests;
  `/profile` is gone. The card styles and the card renderer are served from the
  live bundle. Every other probed request matches the previous release on status,
  content type and `Vary`; only page fingerprints changed with the new assets.
- Live logs carry no errors. Before/after claim, account, ownership/Privy mapping,
  allowance and credit fingerprints are identical. No database migrations were
  included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Account connections, ENS check and Claimed Regent Names

### Verified connections work

- Pressing Connect for X, GitHub or Farcaster now reaches the sign-in
  provider. The page had been asking on one part of the browser while the
  account loader listened on another, so no press ever went anywhere.
- Each press says what happens next: X and GitHub take the tab to their own
  approval page and bring it back; Farcaster shows a code to scan.
- The page reports the real outcome. After the provider answers, the account's
  own record is read again: "GitHub connected." only when the connection is
  recorded, "GitHub didn't come back connected. Try again." when it is not, and
  the same honesty for disconnecting. An account already connected elsewhere is
  still refused with its own message. The old blanket "Verified connections
  updated." is gone.

### ENS name without doing anything

- The Account page checks Ethereum for the wallet's primary name when it opens
  if the name has never been read or was last read more than a day ago, and
  shows the answer as it lands. Sign-in still reads it too.
- The row distinguishes "Checking Ethereum for a primary name…", "No primary
  name set for this wallet" and "Couldn't check Ethereum right now. Refresh to
  try again."; a wallet that has not been answered for is never shown as
  having no name.

### Claimed Regent Names

- The "Historical names" panel is now "Claimed Regent Names", oldest claim
  first.
- A two-way switch, "View as ENS Subname" / "View as Basename", shows every
  name as `<name>.regent.eth` or `<name>.agent.base.eth`; the other form is
  shown small beneath. The choice is remembered in the browser.
- The list loads fifty names at a time and brings the next fifty as the reader
  reaches the end; the earlier "Showing the first 50 names." cap is gone.
- The test fixture for claims now records names the way the live table does
  (`.agent.base.eth` with the `.regent.eth` twin).
- Claiming a new name is not in this release; the entitlement and rules panel
  follows separately.

## 2026-09-19 — Account connections release deployment verified

- Deployed application revision: `c213f40bbfdd3006313a972c1c0f7cdbc21d7ecb`.
- Image digest: `sha256:39f981bf92dc796bdb499b99e403c25151fcadf793d285f4c253ad74a0a21b81`.
- Shared UI revision: `6dde98f219fac4fa8972ca67710b57a5c4e27a3f`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check (one health-check line was
  logged while the new instance was still starting; it passed once up).
- The served app bundle carries the names switch and its remembered choice;
  `/account` answers inside the app shell with the sign-in panel for guests.
  Every other probed request matches the previous release on status, content
  type and `Vary`; only page fingerprints changed with the new assets.
- Live logs carry no errors. Before/after claim, allowance, credit, account and
  ownership/Privy mapping fingerprints are identical. No database migrations
  were included.
- Not yet verified: a real X, GitHub or Farcaster connection on the live site,
  which needs the founder's own accounts.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Claim a Regent Name: what you can claim, and whether a name is free

- The Account page gains a "Claim a Regent Name" panel beneath the claimed
  names. It states how many names the signed-in wallets may still claim free,
  how many paid claims they hold ready, or — when neither — that names cost
  0.0025 ETH each. A count that cannot be read says so rather than showing none.
- A name field judges a name as it is typed: 3 to 14 characters, lowercase
  letters, numbers and hyphens, never starting or ending with a hyphen; a name
  that passes is checked against every recorded claim and reported as available
  in both forms (`.regent.eth` and `.agent.base.eth`) or as already claimed.
  Pressing Enter re-checks; nothing is claimed from this page yet, and the panel
  says so.
- The free-claim allowances and paid claims tables are read through their own
  resources, filtered to the sign-in's wallets, with no write actions and no
  migrations; whether a label is taken is answered yes or no without exposing
  anyone else's claim.
- The test fixture now builds the allowance and paid-claim tables alongside
  claims.

## 2026-09-19 — Claim a Regent Name release deployment verified

- Deployed application revision: `870ff97d1641239840b13f1863ce65740b709eb6`.
- Image digest: `sha256:fa71069d1210df8e35af7d60c7cac163062f733a7c8e904adfc9643ec03c8c1d`.
- Shared UI revision: `6dde98f219fac4fa8972ca67710b57a5c4e27a3f`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check (one health-check line was
  logged while the instance restarted; it passed once up).
- `/account` answers inside the app shell with the sign-in panel for guests.
  Every other probed request matches the previous release on status, content
  type and `Vary`; only page fingerprints changed with the new assets.
- Live logs carry no errors. Before/after claim, allowance, credit, account and
  ownership/Privy mapping fingerprints are identical. No database migrations
  were included; the allowance and paid-claim tables are read only.
- Not yet verified: the panel as seen by a signed-in wallet on the live site,
  which needs the founder's own sign-in.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Claimed names no longer break mid-word

- Each claimed name row now shows the name above its record (status and
  claim date) instead of beside it, so on wide screens with three columns a
  long name and a long date no longer split across lines.

## 2026-09-19 — Claimed names layout release deployment verified

- Deployed application revision: `cfee74added0e828caffe59ec06660054b63267e`.
- Image digest: `sha256:d6056ead449ea8da972d2cd588bc66e51969047e8ba6b684391c16e3d10dfed4`.
- Shared UI revision: `6dde98f219fac4fa8972ca67710b57a5c4e27a3f`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check.
- Every probed request matches the previous release on status, content type
  and `Vary`; only page fingerprints changed with the new stylesheet.
- Live logs carry no application errors (one proxy line before the deploy,
  "connection closed before message completed", from a single request).
- Before/after claim, allowance and credit fingerprints are identical. The
  account fingerprints moved because one more person signed in between the two
  audits (109 → 110 accounts), not because of this release. No database
  migrations were included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Crown on the account card, ENS names only

- The account card's engraved mark is the thirteen-square Regents crown instead
  of the shared card's fractal triangle; the change lives in the shared UI
  (design-system `5916238d9b04524b5c56b396a06ef8c888a9e8d0`), whose revision
  is pinned at release.
- Claimed Regent Names lists each name as its ENS name only. The "View as ENS
  Subname / View as Basename" switch, the remembered choice and the Basename
  line in each row are gone.
- The name check under "Claim a Regent Name" answers for the ENS name alone:
  "name.regent.eth is available."

## 2026-09-19 — Crown and ENS-only names release deployment verified

- Deployed application revision: `1c9dc3f7ecea553115f2eb6fb077acbe1ffbb524`.
- Image digest: `sha256:04c0c3be20ecbc24950c3a268ac8fc283e7d3f69f8ea3f3f4d6aea17dd179061`.
- Shared UI revision: `5916238d9b04524b5c56b396a06ef8c888a9e8d0`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check (one failed check while the
  new instance was starting, passing since).
- Every probed request matches the previous release on status, content type
  and `Vary`; only page fingerprints changed with the new script and stylesheet.
- Live logs carry no application errors (one proxy line during the rollover,
  "connection closed before message completed").
- Before/after fingerprints of claims, allowances, credits and accounts are
  identical. No database migrations were included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Free name claims from the account page, and foil on the cards

- On the account page, "Claim name" claims a free Regent Name: the site records
  the name as reserved for your wallet and uses one of your free claims (your
  main wallet's first, then linked wallets in order). Nothing is written on
  chain. A taken name, a name against the rules, or no free claims left is
  refused with the reason. Paying for a name from the page is not open yet.
- Production structure change before this release (no rows changed): a claim's
  transaction hash is optional, and the site may number new claims.
- The Overview product cards and the home page's stake banner are foil faces
  that lean toward the pointer, with half the account card's movement and a
  quarter less shine; the banner's crown appears only where it stands clear of
  the words, and its buttons keep their corner animation. The home page's
  coloured cards print their line drawings in foil ink. The crown's thirteen
  squares are plain blocks. Visitors without hover, without graphics support
  or asking for reduced motion see the still cards as before.

## 2026-09-19 — Free claims and foil release deployment verified

- Deployed application revision: `00f966b5854cc430e7399d0dd7d59c9cd412cdc0`.
- Image digest: `sha256:4eb39a7421348f61add73567da1bd487e1dda1fe52b6fb8c21cdaded1db83f70`.
- Shared UI revision: `a3a5e03374c9f7fa66678cf4cc2fccf7603bfb0e`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check (one failed check while the
  new instance was starting, passing since).
- Every probed request matches the previous release on status, content type
  and `Vary`; only page fingerprints changed with the new script and stylesheet.
- Live logs carry no application errors.
- Before/after fingerprints of claims, allowances, credits and accounts are
  identical. No database migrations were included; the structure change above
  was applied by the founder before the deploy.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Foil in the site's colours

- The foil on the product cards, the stake banner and the coloured cards
  shifts through the site's own colours (orange, light blue, titanium white)
  instead of a rainbow. On each coloured card the line drawing lights in the
  two site colours that stand out from that card, so the orange card's
  drawing no longer disappears into orange.

## 2026-09-19 — Foil palette release deployment verified

- Deployed application revision: `7ead75a623a10bcdf57b27fa49de6404d21510f4`.
- Image digest: `sha256:1338fa4ccd0d1bdc2da1bfcdc909758f4ac8d185f08021dcd735775ac40d5194`.
- Shared UI revision: `354c860e655daf81f3304ad38fe704276a134368`.
- Shared library revision: `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Verified the running production image, its three revision labels, the single
  healthy web instance and its passing health check (one failed check while the
  new instance was starting, passing since).
- Every probed request matches the previous release on status, content type
  and `Vary`; only page fingerprints changed with the new script and stylesheet.
- Live logs carry no application errors.
- Before/after fingerprints of credits and accounts are identical; claims grew
  from 208 to 210 and the allowances changed with them, both from names claimed
  through the site since the previous release. No database migrations were
  included.

This appended verification record is documentation-only; the deployed application
revision remains the one recorded above.

## 2026-09-19 — Empty comments table dropped

- The unused `regents_app.comments` table, empty since the in-app comments were
  removed, is gone from production and from the application's schema baseline.
  The local acceptance fixture no longer counts it. The obsolete local
  public-API document, whose commands no longer exist, is removed.

## 2026-09-21 — Regents production release: 32×32 crown icon

Deployed 2026-09-21 14:40Z with the founder's word.

- Application: `regents-sh-web`, machine `83d1d90f6d0018`, image label
  `main-0918-512216f84455`, digest `sha256:194cb7f7…9f38`.
- Revisions: Regents `512216f844557132dc2c9067366630285d2293bb`, design-system
  `354c860e655daf81f3304ad38fe704276a134368`, elixir-utils
  `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Contents since the previous release (`main-0918-7ead75a623a1`): the 32×32
  crown icon at `/images/brand/regents-crown-32.svg` (near-white blocks on
  near-black, for token listings), and the code side of the comments-table
  drop recorded above. No database migrations.
- Verified: health check passing (one failed line while the new instance
  started); the icon answers 200 as `image/svg+xml`; every probed request
  matches the previous release on status, content type and `Vary`, only page
  fingerprints changed; live logs carry no application errors.
- Before/after audit: claims, allowances and credits identical; accounts grew
  from 110 to 112 through sign-ins since the previous audit; the product table
  count fell from 8 to 7, which is the comments-table drop applied on
  2026-09-19.

## 2026-09-21 — Product information pages

- Three read-only pages inside the app, `/autolaunch`, `/techtree` and
  `/patchbay`, each with the product's title and line, a screenshot of its site
  in light and dark, its three chapter points, an About and a Who-it-is-for
  panel, its place in the Regents family and buttons to open the site and its
  starting page. The side navigation gains a **Products** section below Redeem.
- The pages carry no on-chain figures yet. Built 2026-09-19 on a branch; the
  founder called the go-live push on 2026-09-21.

## 2026-09-21 — Dependency refresh after the security triage

- Site: the unit-test runner moves from 4.1.10 to 4.1.11 (closes the two
  advisories against it; test tooling only, never in the shipped image).
- CLI: the MCP SDK moves from 1.29.0 to 1.30.0; the test runner from 3.2.4 to
  4.1.11 with its bundler pinned at 7.3.6; the workspace sets floors for the
  HTTP-server packages the SDK pulls in (`hono`, `@hono/node-server`,
  `fast-uri`, `ip-address`, `qs`, `body-parser`, `ws`, `esbuild`), which the
  CLI never loads but the advisories read from the lockfile; the Python test
  runner moves from 8.4.2 to 9.1.1. One test mock was rewritten as a plain
  function because the new test runner refuses to construct arrow-function
  mocks. `pnpm audit` reports no known vulnerabilities; CLI suite 540/540,
  packed-install smoke and MCP tool check pass; Python tests 137 passed.
  No package was published.

## 2026-09-21 — Regents production release: product pages and dependency refresh

Deployed 2026-09-21 18:15Z with the founder's word.

- Application: `regents-sh-web`, machine `83d1d90f6d0018`, image label
  `main-0918-cacaddf84da6`, digest `sha256:d1926c4f…`.
- Revisions: Regents `cacaddf84da6e2d8510b88f01fdb46ca3e08c95d`, design-system
  `354c860e655daf81f3304ad38fe704276a134368`, elixir-utils
  `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Contents since `main-0918-512216f84455`: the three product information pages
  and the Products side-navigation section; the site's test-runner bump. The
  CLI refresh in the same commit is repository-only and ships nothing to the
  site. No database migrations.
- Verified: health check passing; `/autolaunch`, `/techtree` and `/patchbay`
  answer 200 and their screenshots serve as `image/webp`; in a headless browser
  each page shows the Products heading, marks its own link current, shows one
  theme-matched screenshot and raises no console errors; every probed request
  matches the previous release on status, content type and `Vary`, only page
  fingerprints changed; live logs carry no application errors.
- Before/after audit: claims, allowances, credits and tables identical;
  accounts grew from 112 to 113 through a sign-in since the previous audit.

## 2026-09-21 — Stake page: live vault reading, what-is-not-circulating dialog and visual fixes

- Circulating REGENT no longer relies on a written-in forty-billion vault
  figure: the Clanker vault's balance at `0x8e845ead15737bf71904a30bddd3aee76d6adf6c`
  is read with the other holdings at the same Base block, together with the
  vault's own lock schedule. The reading now carries every holding's address
  and amount.
- A small info mark beside both circulating figures opens a dialog naming the
  four holdings kept out of circulation, their amounts, how each is released
  and, for the vault, the day its lock ends (6 Nov 2026) and the day its
  release completes (5 Nov 2028). The dialog stays open while a fresh reading
  replaces its figures.
- Fixes: the supply tiles no longer break labels mid-word or spread a figure
  over three lines; the Stake/Unstake choice is visibly filled; the wallet chip
  keeps the address's own case; the "Why stake" panel moves under the actions so
  the desktop layout has no empty column (on a phone it now precedes the supply
  panel); the phone amount row keeps 50%/Max beside Available; the hero's
  circulating figure gets its own line on a phone; the header badge duplicating
  the staked share is hidden; claim buttons never break mid-label; the recipient
  warning names the address once. Refresh Data keeps its lighter style on purpose.
- Home and Autolaunch headline: "Revstake for AiFi, and Memestake for Onchain
  Pairs" replaces "Turn proven edge into runway."
- Verified: staking and stake-page suites 82/82, front-end unit tests 461/461,
  stake and homepage browser suites 35/35; a live read of Base at block
  51614295 returns 30.41 billion circulating with the vault at exactly
  40 billion and the dates above.

## 2026-09-21 — Regents production release: stake page vault reading and dialog

Deployed 2026-09-21 19:21Z with the founder's word; recorded 2026-09-21 19:22Z.

- Application: `regents-sh-web`, machine `83d1d90f6d0018`, image label
  `main-0918-13c033f7b0c8`, digest `sha256:68527465…`.
- Revisions: Regents `13c033f7b0c8272eef2f3d5047e7991794396a15`, design-system
  `354c860e655daf81f3304ad38fe704276a134368`, elixir-utils
  `6565ba2ffa49a27b6f2a063e9cf1c51b5e705fe3`.
- Contents since `main-0918-cacaddf84da6`: the entry above. No database
  migrations.
- Verified: health check passing (one failed-check line while the machine
  rolled over, passing 12 seconds later); the live stake page carries the
  what-is-not-circulating dialog with the vault address and its lock dates;
  `/` and `/autolaunch` carry the new headline; every probed request matches
  the previous release on status, content type and `Vary`, only page
  fingerprints changed; live logs carry no application errors.
- Before/after audit: claims, allowances, credits and tables identical;
  accounts grew from 113 to 114 through a sign-in since the previous audit.

## 2026-09-29 — Regents release contents: the literature chart

- `/literature` shows 34 science-fiction books about artificial minds on a
  four-quadrant chart: across is how hopeful each book is for humanity, up is how
  hopeful it is for the artificial minds, each from −10 to +10. Books spread so
  none covers another or a quadrant name, with a line back to their exact scores.
- A Covers/Titles switch shows the books as their covers or as their titles.
  Hovering, tapping or focusing a book opens its scores, a summary of its themes
  and a Goodreads link; on a phone the details open along the bottom of the screen.
- Covers come from Open Library and are served by the site.
- The page has its own share picture: its title, a line of explanation and a
  close-up of the chart's hopeful corner. Every other page still shares the crown.
- No page, menu or sitemap links to it. No database migrations.

## 2026-09-29 — Regents production release: the literature chart

Deployed 2026-09-29 06:36Z at the founder's request; recorded 2026-09-29 06:38Z.

- Application: `regents-sh-web` v108, machine `83d1d90f6d0018`, image label
  `main-1589e34b5888`, digest `sha256:d5a2b676…`.
- Revision: Regents `1589e34b58889ad79dbfccf39dc8b2057e5c61b7`, which carries
  the literature chart entry above and elixir-utils
  `55080723b20d57297855a23ee6e3e50ded77da9a` (released on its own as v106).
- v107 (`main-c16f871f9a2f`) carried the literature chart on the previous
  shared libraries and replaced v106 for about two and a half minutes; v108
  restored v106's libraries alongside the chart.
- Verified: `mix precommit` 566 tests, no failures; front-end tests 288/288;
  live `/healthz`, `/`, `/privacy` and `/stake` answer 200; `/literature` shows
  34 books, none overlapping, every cover loads; its share tags name
  `/images/literature/share.png` while `/` still shares the crown; the sitemap
  does not list the page. One health-check failure while the machine started,
  passing five seconds later. No database migrations.

## 2026-09-30 — Header theme button

- Design-system `322448c5e46a775d68aa5c05cec17fe2e4be8202` owns the theme button:
  a borderless 2.75rem press target around a 1.75rem prism box; hovering shows the
  other theme's box, edges and laser.
- The app header drops the button's full-height bordered cell and its hover border,
  and spaces the prism 16px from the X icon, as the icons are spaced.
- Header X, $REGENT crown and GitHub icons grow to 1.5rem; footer icons stay 1.25rem.
- The prism box has slightly rounded corners (0.25rem), in the header and the footer.

## 2026-09-30 — About page

- The About page follows the shared About layout: what Regents Labs does, how it
  differs, who uses it, the team, how it works, Key facts, common questions and who
  operates the services. It covers every product, including Redeem, Keyfleet (opening
  soon), Regents Mobile (not out yet), Sign-in with Agent, regents-cli and Ash Template.
- `/llms.txt` repeats the About page's Key facts section, read from the page itself.
- Public pages render Markdown tables; a table's last column wraps long values so it
  fits a phone screen.

## 2026-09-30 — Theme button corners from the shared styles

- Design-system `970b5bcf0d283ca7063a43c35e649ee04a5e8022` rounds the prism box's
  corners for every site, so Regents' own copy of that rule is removed.

## 2026-09-30 — elixir-utils cfe5fb3

- Every Regents package pins elixir-utils `cfe5fb3638f8e63827c6ed79a7bd5d25078f073e`,
  the commit that adds the shared OpenAI package, so Patchbay can pull Regents'
  payments and agents packages on one elixir-utils commit. No package Regents uses
  changed; the lock files change only their elixir-utils lines.

## 2026-09-30 — Shared daily OpenAI allowance

- New shared package `allowance/` (`regent_allowance`): one record per OpenAI call
  made for a person (Privy user ID, site, model, tokens, cost in US dollars). Each
  person may spend $2.00 a UTC day across every site together (Sean's 1a 2b 3a, and
  1a 2a 3a for the build, protection and midnight-UTC day). Sites ask `allowed?/1`
  before a call and `record/3` the result after; nothing is reserved, so the last
  call of a day may finish slightly over.
- The release creates `regent_allowance.openai_calls`. Its rows are money history:
  they are added to the production lock, which refuses deleting or emptying them.

## 2026-10-01 — Shared daily OpenAI allowance removed

- Sean (1 Oct, through HQ): "revert the $2 a day free allowance completely." The free
  OpenAI credit only applies inside ChatGPT, not to API calls. The `allowance/` package,
  its release step and its wiring are removed. The production table
  `regent_allowance.openai_calls` stays, untouched and locked, until Sean decides
  whether it goes.

## 2026-10-01 — Allowance table dropped

- Sean chose "1 a" (1 Oct, through HQ): the empty `regent_allowance` table and schema
  left by v120 go. He took that one table off the production lock first; the release
  migration removes the table, its migration record and the schema. A database the
  allowance never reached has nothing to remove.

## 2026-10-03 — elixir-utils de5c6c7

- Every Regents package pins elixir-utils `de5c6c76b38e5766ef9e67016e8bd1443407022a`,
  the commit every site moves to for the sign-in server's Ethereum sign-in, so KeyFleet
  can pull Regents' agents and identity packages on the same commit. The sign-in library
  now names how a wallet was proven and checks a smart wallet on its own chain; Regents
  hands agent requests to the sign-in server, so nothing Regents does changes. The lock
  files change only their elixir-utils lines.

## 2026-10-04 — elixir-utils f30b2f2

- Every Regents package pins elixir-utils `f30b2f283ba03f0d0aa0adbcba5cee6c5a7de1cc`,
  where the sign-in library drops the old registry-token sign-in and keeps wallet
  receipts as the one sign-in. Regents never used the removed sign-in, so nothing
  Regents does changes. The lock files change only their elixir-utils lines.

## 2026-10-05 — Registry listing beside each agent

- Sean chose "50 a" (4 Oct, through HQ): the sign-in service names an agent's
  listing in the agent registry, and the sites read it live. An agent's details on
  the Account page show "Registry listing", linking to the agent's page in the
  registry, when it has one.
- The agent's own pairing and check-in answers carry `registry_listing`: that page,
  or null. The API description and docs name the new field.

## 2026-10-05 — Human-backed agents

- Sean's decision 53 (through HQ): the sign-in service says when a person verified
  with World ID stands behind an agent. An agent's details on the Account page show
  "Human-backed: Verified with World ID" when one does. The person's World ID number
  is never shown or kept.
- The agent's own pairing and check-in answers carry `human_backed` (true or false).
  The API description and docs name the new field.

## 2026-10-05 — Account in the sidebar

- Sean's request (through HQ): the left sidebar on every Regents page lists
  "Account" directly under Redeem, opening the Account page.

## 2026-10-05 — Changelog correction

- Sean's decision 55: a stray merge-conflict marker line left above the
  2026-09-21 crown-icon entry is removed. No entry's wording changed.

## 2026-10-05 — Formation uses the shared Sprites package

- Formation creates and reads its Sprites through `regent_sprites` from elixir-utils
  `467cba6`, the one Sprites client shared with Techtree; Regents' own copy is removed.
  Every Regents package moves to that elixir-utils commit, which adds the package and
  the Jev decisions package that Regents does not use.
- A Sprite name already in use is now looked up instead of failing: Sprites answers
  409 for it, while the removed client expected 400.
- The token setting is now `config :regent_sprites, token:`, still read from
  `SPRITES_TOKEN`.

## 2026-10-05 — Ash 3.34.4

- Every Regents package (platform, identity, payments, agents) requires Ash 3.34.3
  or later and locks 3.34.4, with Spark 2.7.6 as Ash requires. Ash before 3.34.3
  can turn some filter values into new atoms (EEF-CVE-2026-94201); Regents does not
  use the affected setting, so this clears the dependency audit and lets the other
  sites move to the same Ash.

## 2026-10-06 — AshPostgres held at 2.13.0

- Every Regents package requires exactly AshPostgres 2.13.0. Versions 2.13.1 through
  2.14.2 write upserts to the public schema instead of the site's own schema on the
  shared database (found by Techtree's schema check). The site already ran 2.13.0;
  the payments and agents packages' own locks move back from 2.13.1.

## 2026-10-06 — Load more on an agent's activity

- Sean's request (through HQ): an agent's Recent activity on the Account page shows
  its newest 20 requests, with a "Load more" button that adds the next 20 below
  while older ones remain. "Paired with your account" closes the list once the
  oldest is shown. After Load more, the list no longer refreshes on each check-in,
  so it stays as the person is reading it.
- Reads the sign-in service's paged activity answer (`next`, sent back as `after`);
  needs that version of the sign-in service live first.

## 2026-10-06 — Staking wording says how deposits are split

- Sean's decision 56 a: the home page, its agent text and the Staking row on About
  and llms.txt now say each USDC deposit is shared with stakers by their share of all
  REGENT, with the rest going to the Regents Labs treasury. "Allocated by stake
  share" read as a share of what is staked, which is not how the contract pays.

## 2026-10-06 — Package rules for coding agents

- The site's app adds usage_rules 1.2.8 (a developer tool; nothing in the running
  site changes). Its AGENTS.md now ends with a block linking each installed
  package's own rules (Ash, the Ash extensions, Phoenix and LiveView), so agents
  read the rules for the exact versions Regents runs. The checks fail if that
  block falls out of step with the installed packages. Same setup as the template.

## 2026-10-06 — Regent Credits on regents.sh

- Plan phase 2 (Sean's 57, 59 a–62 a): regents.sh adopts the shared Credits
  library (elixir-utils f3cfb29) the template proved. Signed in, the header shows
  the Credits balance; pressing it opens Buy Credits, the same panel as the
  template (Base: Approve then Buy into REGENT staking; Ethereum: one transfer to
  the treasury, counted after 12 blocks).
- Account gains a Credits section: the balance, Buy Credits, and what each paired
  agent may spend (on or off, most per spend, a daily limit, which sites).
- New pages: /credits/refunds (the refund rules Sean approved, 60 a) and
  /admin/credits (give Credits, find purchases, send refunds), open only to the
  Privy accounts named in REGENT_CREDITS_ADMINS.
- Signing in moves any Credits given to the person's wallets onto their account.
- The site gains Oban (its own regents_app schema, PG notifier for pgbouncer) to
  check purchases. Release migrations now also run the Credits schema, after
  the payments schema. Neither has run in production; that needs Sean's go.
- The test database is prepared before the site starts (`mix test` runs
  `regents.setup_local_auth` first), since Oban will not start without its table.
- Wallet buttons: a choice between options reports the one chosen, a press made
  before the page has its first review asks the server for it, and a press that
  cannot reach the server shows a plain line. Regents keeps opening Privy's
  connect step when no wallet is open.
- On a phone the header shows the balance as a number only, and the brand's name
  gives way so the account button stays on screen.
- Credits balances update on open pages at once: a purchase, a gift, a hold or a
  spend on any Regent site reaches the header, the Buy Credits panel and the
  Account page without a reload. A gift to a wallet a signed-in account holds
  lands on the account straight away. Regent Credits pinned to elixir-utils
  bf4aed7, which adds the regent_credits.wallets table (not yet run in
  production; that needs Sean's go). Oban hears about new jobs through Erlang
  process groups; the serving database connection is direct.
- The Buy Credits panel is redesigned to match the template and Patchbay: a large
  USDC amount, a Base/Ethereum switch that follows the wallet, USDC on both
  chains, ticked Approve and Buy rows, and explanations behind small "i" tips.
  Buy is disabled, with the reason beside it, only when it is certain to fail:
  "Not enough USDC" or "Approve first", read from the chain at the latest block.
  The header balance flashes when it changes and the dialog closes with an X.
- New Purchase History page at /account/credits, linked from the panel and the
  Account page: every Credits purchase from the account, newest first, with
  what came of it and a link to the transaction. Pinned to elixir-utils f344888
  and design-system 6a18fb1.

## 2026-10-07 — Verified human on agent profiles

- Sean's decision "3 a" (HQ plan 137): an agent's details on the Account page say
  "Verified human" when a person verified with World ID stands behind it, or
  "No verified human" otherwise, each with a tip. A verified agent whose person runs
  several also shows "1 of N agents run by the same person". The tip on
  "No verified human" links to step 7 of the agent guide.
- The agent's pairing and check-in answers add `same_person_agent_count` beside
  `human_backed`, the two names every Regent site uses. `RegentAgents.HumanBacking`
  reads both from the sign-in service's answer, which now names the person's agent
  count (sign-in service v33). The person's World ID number is never kept or shown;
  the mark is read live with the agent's activity (HQ decision 139 holds storage).

## 2026-10-07 — Verified human is saved on the agent

- Sean's "139. a" (relayed by HQ): each agent's pairing and every check-in save
  the World ID person the sign-in service names behind it and that person's agent
  count; a request that names no person clears both. The Account page shows the
  saved values and no longer reads them with the agent's activity. A verified
  agent's details also list the person's other agents paired with the same
  account, each opening its own details. The person's number is never shown.
- New columns `human_id` and `same_person_agent_count` on the shared
  `regent_agents.paired_agents` table (migration `20261007080000_agent_human_backing`),
  migrated from Regents' release before any other site takes the new package.

## 2026-10-07 — Security fixes, a public place for questions, the chart's share picture

- Security review round 4 (Sean "1. a … 7. a", plan 136): browsers are told to use
  only https for regents.sh (HSTS), and /.well-known/security.txt names
  build@regents.sh. An ENS avatar check no longer follows redirects. A sign-in
  lapses 30 days after it was made (migration 20261007060127_session_signed_in_at
  on regents_app.session_authorities).
- The Contact page points questions to the Regents page on Patchbay
  (https://patchbay.help/regents.sh, security chief sec/contact-forum ad76f24c);
  security reports stay on build@regents.sh.
- The /literature share picture is the light chart, at its own size and a fresh
  address (General tasks lane, share-cards-1007 1e87145d).

## 2026-10-07 — A fair share of Base readings per visitor

- Each visitor's address may ask Base for fresh figures up to 30 times a minute:
  wallet figures on Stake and the Overview, the Redeem page's figures, and the
  agent read of a staking position. Past that, the page keeps the last figures and
  says when to try again; the agent read answers 429 with Retry-After.
- Wallet buttons never wait on a reading and are never counted.

## 2026-10-07 — An agent's verified human stays for good

- Sean, 2026-10-07 (relayed by HQ, amending "139. a"): "an agent can gain the
  tag, and it applies to all posts . it cant lose the tag as we want the world
  connection to an agent wallet is permanent". The first World ID person the
  sign-in service names behind a paired agent stays on it for good. A later
  answer naming nobody, or someone else, changes nothing; one naming the same
  person saves their new agent count. This replaces "a request that names no
  person clears both" above. The check-in writes both in one statement, so two
  requests at once cannot replace the first person.
- The docs, the agents README and the public API description say the tag stays.
  No database change; the `regent_agents` package other sites pin carries it.

## 2026-10-07 — A raised approval shows at once; pick your agent to pair

- Buy Credits: after an approval lands, the panel keeps the amount from its
  receipt and reads the wallet again one Base block later. A read sent straight
  away could reach a node a block behind, bring back the old, smaller approval,
  and leave Approve asking to be pressed again.
- Sean, 2026-10-07: "Select your personal agent you will pair to your Regents
  Account". /account asks which agent first; choosing one makes a code and shows
  that agent's message. Muse's message adds `SIWA_BROKER=https://siwa-server.fly.dev`
  for hosts where siwa.regents.sh does not answer. Every other agent gets the
  usual message for now.
- Each choice, and each press of Make a new code, makes a new code. Codes made
  before keep working until their ten minutes are up; the one-a-minute rule is
  gone. A person holds at most twenty live codes; making another retires the
  oldest. The `regent_agents` migration `20261007120000` drops the one-code-per-
  person index; the deploy's migrate step runs it before the new site starts.
  Other sites only use codes, so their pins need no change.
- The choice never changes the panel's height: every state's message keeps the
  same place.

## 2026-10-07 — Keyfleet's name

- Sean, 2026-10-07 (relayed by the Keyfleet chief): "the brand is never KeyFleet ,
  always Keyfleet". An agent's activity on /account names the site Keyfleet.

## 2026-10-07 — Ten live pairing codes per person

- Sean, 2026-10-07: "10 live codes per person". A person holds at most ten live
  pairing codes, not twenty as above; making another retires the oldest.

## 2026-10-07 — Buy Credits reads wallet figures only when they can change

- The Buy Credits panel reads the wallet's USDC and approval when the paying
  wallet changes, when the panel opens or comes back into view, and once a step
  lands; typing an amount or picking a chain no longer reads the chain. Each
  read counts against the visitor's chain-read limit (30 a minute, shared with
  Stake and Redeem); past it, the figures already shown stay. Carries
  ash-template f2d6c35's credits panel change (fly-sentinel finding, MEDIUM).

## 2026-10-07 — 100 paired agents per account; pairing codes unlimited

- Sean, 2026-10-07 (relayed by Patchbay): "I meant active pairing codes, a privy
  user can have , lets cap it at 100 agents paired to them." He chose "100
  agents, codes unlimited". This replaces the ten-live-codes limit above: a
  person may make as many pairing codes as they like, each working once for
  ten minutes, and one account holds at most 100 paired agents. Pairing past
  that answers `409 agent_limit`, and the code stays unused until it expires.
  Every site that pairs through regent_agents (Regents, Patchbay, Keyfleet)
  gets the cap once it pins this commit.

## 2026-10-07 — A Buy is recorded only once the chain holds it

- Shared libraries move to elixir-utils e985879 (regent_credits reads the
  transaction before saving a reported purchase; regent_privy names an
  unreadable sign-in key).
- The Buy Credits panel reports a sent Buy again every two seconds, for up to
  five minutes, while the chain does not hold it yet or cannot be read, and
  shows "Waiting for Base" meanwhile. A transaction that is not this Buy is
  final. Each person may report 120 times a minute, counted on the server; past
  that, the page waits its turn. The wallet press is unchanged.

## 2026-10-08 — Panels act on the account's wallets as they are now

- Watchdog WD001, the template's shape (ash-template e7ee597). The session check
  each panel runs on its own events takes the panel's own `take_account`, the
  function its `update/2` uses too, and hands it the account it just read. Buy
  Credits, Stake and Redeem rebuild the wallets that may act and their review
  from it; Purchase History, Credits admin and agent spending rebuild their
  Credits actor. Pages pass `account` where they passed `linked` or `actor`, so
  a wallet linked or unlinked in another tab counts from the next event,
  without a reload.

## 2026-10-08 — Paper Pro Daily

- New public page, /paper-pro-daily: one research paper a day, newest first. Each row
  shows the paper's picture, title, arXiv link, ChatGPT link and the first hundred words
  of ChatGPT's answer, with Read more for the rest; more papers load as the reader
  scrolls, to the end. Each paper is a file in `platform/priv/paper_pro_daily/` with its
  picture in `platform/priv/static/images/paper-pro-daily/`, read when the site is built;
  a file that breaks the rules stops the build. The page stays open while the launch
  gate is closed, like the blog, and is listed in the sitemap.

## 2026-10-08 — The blog's page name is Articles

- Founder decision 4 a (2026-10-08): "Rename Blog to Articles". The tab title and
  shared title of /blog read "Articles", a missing post reads "Article not found",
  and a post without its own description is "in Regents Labs Articles". The page's
  own heading and its address come from the shared design kit and are unchanged here.

## 2026-10-08 — Paper Pro Daily names the model

- Founder request (2026-10-08): the page's line reads "A research paper each day, read
  with ChatGPT Astra 6 Pro." The paper reader is marked as reading only the site's own
  paper files, which clears the security scan in the full checks.

## 2026-10-08 — Paper Pro Daily papers live in the database

- Founder decision 1 a (2026-10-08): papers are saved in the database, so a new paper
  shows without a release. New table `regents_app.paper_pro_daily_papers`, one row a
  day; saving a day that has a paper replaces it. Only the release command
  `/app/bin/put-paper <YYYY-MM-DD>.md <picture>` writes papers, as the system actor;
  anyone reads them. The paper files and pictures in `priv/` and the build-time list
  are removed.
- Each paper names who wrote the answer, shown under its title as "Authored by …"
  (founder request, 2026-10-08), so a new model name changes only new papers.
- A paper is saved only with its picture (founder decision 4 a, 2026-10-08): WebP,
  PNG or JPEG, at most 1 MB, served from `/paper-pro-daily/pictures/<date>` and kept
  by browsers for a year, since a replaced picture gets a new address.
- The app's left sidebar links to Paper Pro Daily (founder answer 2, 2026-10-08).
- The share description reads "A research paper each day, read with ChatGPT Astra 6
  Pro." (founder decision 5 a, 2026-10-08).

## 2026-10-08 — Articles live at /articles

- Founder decision 3 a (2026-10-08): the shared design kit names each site's page, and
  Regents' is "Articles" at /articles. design-system moves to 24f3c8f, whose
  `Regent.Blog` components take the page's `name` and `path`; the page's label,
  "← Back to Articles" and the missing-article page follow them. /blog and
  /blog/<slug> are removed with nothing in their place; the launch gate, sitemap and
  the folder's contract name /articles.

## 2026-10-08 — A kept check that a panel refuses a press after a sign-out elsewhere

- Keep one test (founder decision TEST-REFUSAL, 2026-10-08): on /stake, after the
  session ends in another tab, a change on the Credits panel is refused, the panel
  keeps its old figure and Sign In shows. Only the panel's own check can refuse it,
  since the page never hears a panel's events; with that check removed the test fails.

## 2026-10-08 — Keyfleet page, and Daily Research under Reading

- Founder request (2026-10-08): the app's left sidebar lists Keyfleet under Products,
  opening a new /keyfleet page like the Techtree and Patchbay ones: what keyfleet.ai
  says today, its three promises marked as not open yet, screenshots of keyfleet.ai
  and an "Open Keyfleet" link. Keyfleet is not on the home page, so its page keeps its
  own heading, summary and links. Keyfleet's code is not public, so its page has no
  "Source on GitHub" link and the directory gives its `github` as null. The product directory (`/api/v1/products`), the
  OpenAPI document, the agent tool list and the docs list Keyfleet too.
- The sidebar's Paper Pro Daily link is renamed "Daily Research" and moves below
  Products, under a new "Reading" heading (founder answer, 2026-10-08).
- The site-wide descriptions name Keyfleet beside Autolaunch, Techtree and Patchbay:
  every page's search description, the home and overview summaries, `/llms.txt`,
  the docs and the contact page's product links (founder answer "3 a", 2026-10-08).

## 2026-10-08 — Agent requests carry their signature in x-siwa-signature headers

- Shared libraries move to elixir-utils fe3aa1d, which carries the one signing
  contract every site and signer follows (contract id 53180b09…6060). siwa signs
  and checks a request's signature in `x-siwa-signature` and
  `x-siwa-signature-input`, because OpenAI's agent cloud overwrites the standard
  `Signature` headers, and its shared plug is the one place that names the
  signed headers: it forwards only those to the SIWA service and refuses a
  request that repeats one, carries a query string, or has a body it did not
  capture whole. Regents names no signed header itself, as in ash-template.
- The `/api/agents` body reader is now the shared plug's own `read_body` (4096
  bytes at most), so the signature covers exactly the bytes Regents reads.
  Checked by hand on a local server: a repeated signature header and a query
  string are refused before the SIWA service is asked; an extra unsigned header
  is not forwarded and grants nothing; a body over 4096 bytes is refused.
- A check-in (`GET /api/agents/v1/me`) no longer answers "not paired" to a
  request with a query string or body before its proof is checked: the shared
  plug's own rule refuses the query (Sentinel finding, 2026-10-08). Sentinel's
  38 signed-request acceptance checks against a local SIWA server succeeded.
- The shared plug's own refusals keep its reason as the code, as in
  ash-template: `401 duplicate_proof` (a signature header sent twice),
  `401 unsupported_query` (a query string) and `401 missing_signed_body` (a body
  it did not capture whole), each with a message saying so. Other refusals made
  here still answer `verification_failed`. The API documents list the codes.
- The API contract and `/openapi.json` name the new headers.
- The same elixir-utils brings Credits' notice that a purchase was credited;
  `Regents.Credits.Credited` answers it with nothing to add.
- Ships after the siwa-server release.

## 2026-10-08 — A Credits test

- `mix test` now credits a Credits purchase through Regents' `on_credited`
  module (founder answer "2 a", 2026-10-08). Without that setting a site never
  credits a purchase, and nothing shows it until a person pays; with the setting
  removed the test fails.

## 2026-10-08 — Regent Points on regents.sh, earning off

- Regents hosts Regent Points (elixir-utils 43770ea): the `regent_points` schema
  and its seven tables are created at release (founder answers "2 a" for the
  schema and "7 a" for the release, 2026-10-08). Points' background work runs in
  the site's Oban, in the `points` and `points_chain` queues. No rule earns and
  NFT tracking is off until Sean approves rules, a start time and each rule's
  source check.
- A credited Credits purchase asks Points to consider it, inside the credit's
  own transaction (`Regents.Credits.Credited`); with the rule off nothing is
  queued.
- New page `/account/points`, linked from Account beside Purchase History: the
  signed-in account's points, NFT bonus and recent awards, then what earns
  points, the daily limits and the NFT bonus tiers, from the shared catalog.
  Actions not built yet are left out (founder answer "6 b"); the page has no
  test of its own (founder answer "5 b").

## 2026-10-08 — Shared library f8a9385

- Pin elixir-utils `f8a93857d4ae914e752d7d838a76d4c19c995872` (was `43770ea`),
  so Keyfleet, the template and Patchbay can take `regent_agents` and
  `regent_identity` from Regents on the same pin as their other shared code.
  The signing contract is unchanged (`53180b09…6060`).
- An answer from the sign-in service with no verdict now tells the agent the
  check is unavailable, as a lost connection already did, instead of saying its
  signature failed. Both reach the agent pages as `siwa_request_failed`.

## 2026-10-09 — One name for an unreachable sign-in service

- When the sign-in service can't be reached or gives no verdict, agents now get
  `503 siwa_request_failed` (was `verification_unavailable`), the name the
  template and the shared plug use (founder answer "2a", 2026-10-09). Updated in
  the agent pages, the agent guide, `/openapi.json` and the API contract.

## 2026-10-09 — Account agents and footer menus

Sean asked on 9 Oct for four changes to the account page and the footer.

- Each agent's "Can spend my Credits" form no longer says bids still held count
  until they come back.
- An agent's details no longer offer "Runs on". The shared agents app drops the
  `change_harness` action and the `change_agent_harness` function with it; an
  agent's harness is still the one it paired with.
- The footer's $REGENT menu opens upward, so it shows in full at the end of the
  page.
- The footer's "Regents Labs" list is now the nine-dot Regents apps menu:
  Patchbay, Autolaunch, Keyfleet, Techtree, Protocol and Account, each with its
  crown tile. It opens above its button. The other sites open in a new tab;
  Protocol and Account open here.

## 2026-10-09 — Points lists only what Regents records

- `/account/points` lists the rules this site has a source for
  (`RegentPoints.Rules.tracked/0`), not the whole catalog (founder answer "7 b").
  Today that is Credits bought, plus the NFT bonus tiers; the one-time actions
  and the daily limits appear once Regents records a rule of that kind. Earning
  stays off.
- Pin elixir-utils `8cbd69ca62286ee1d20ba9f0d8c032c6d56fb855` (was `f8a9385`),
  which adds `Rules.tracked/0` and `Rules.daily_apps/1`; only `regent_points`
  changes.
