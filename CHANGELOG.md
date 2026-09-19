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
