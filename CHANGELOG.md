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

## 2026-10-09 — Points NFT bonus at the end of each 30-day period

- Sean, HQ thread, 2026-10-09 04:56Z, item 6: the NFT bonus is no longer saved
  with each award. `/account/points` shows the tier the account's linked wallets
  hold now, read from Base when the page opens ("3 NFTs now · +45% at the end of
  this period"), and lists each period's bonus once tallied. Awards show
  points only. Tiers are 1–2, 3–6 and 7+, adding 20%, 45% and 75%.
- Sean, this thread, 2026-10-09 ~05:30Z: "1 a 2 at the end of a period, which
  lasts for 30 days. 3 a". The bonus is tallied at the end of each 30-day period
  counted from the program start, not each calendar month; the percentages stay;
  Regents runs the Points schema change with this release.
- Regents is the one tally site: a daily Oban cron runs
  `RegentPoints.TallyPeriods` at 00:15 UTC. The minute NFT transfer watch, the
  sign-in holdings refresh (`Regents.Points.TrackWallets`) and the
  `points_wallet_holders` account read are removed. The Credits purchase check
  no longer sends wallets.
- The Points schema gains `period_bonuses` and loses the transfer cursor table and
  the saved holdings columns (migration `20261009053234_period_bonus_tally`),
  run in production with this release under Sean's 3 a. Earning stays off.

## 2026-10-09 — Points on the pushed elixir-utils 58acbc4

- Sean in the HQ thread, 2026-10-09 05:59Z (relayed): "6. a". Every elixir-utils
  pin moves to `58acbc4742ea8acded42e8fb40816ac6e0400aaa` (Sentinel CLEAR 06:13:35Z).
  A tallied period's bonus now follows awards checked after the tally and
  corrections, at the tier saved at the tally; the tally no longer waits for
  actions still being checked. An award whose last attempt fails or raises is
  rejected as `award_failed`.
- The Credits purchase check reads the purchase's decimal amount through
  `RegentCredits.Chains.micro/1`. Earning stays off; switching it on waits on
  Sean's PTS-SNAP (one snapshot block per period).

## 2026-10-09 — Credits read every Base deposit; Buy is Base only

- On elixir-utils `58acbc4742ea8acded42e8fb40816ac6e0400aaa`, which carries the
  Credits reader (`f3157529`). Regent Credits now reads every Credits deposit on Base from the chain once a
  minute and credits it, whether or not a page reported it. A deposit from a
  wallet no account holds waits under that wallet until it signs in. Purchase
  and refund amounts are USDC to the millionth. The library's migrations add
  `regent_credits.deposit_cursors` (Base starts at block 52,227,727), make
  `purchases.privy_user_id` optional, key purchases per wallet, store exact
  amounts and check that wallets and hashes are lowercase.
- `Regents.ChainClient` reads logs (`logs/2`), and a node that answers with a
  JSON-RPC error gives `{:error, {:rpc, error}}`, so the reader halves only a
  span the node refused. Other reads through `Regents.WalletActions.Rpc.request/3`
  are unchanged.
- The Buy Credits panel buys on Base only (founder answer "2 b"): the
  Base/Ethereum choice, the Ethereum USDC figure, the Ethereum wording and the
  Switch Chain button are gone; the rate reads "1 USDC on Base buys 1 Regents
  Credit". Each press asks the wallet onto Base, and the send names Base's chain
  id. The `OnchainSteps` hook's `data-refresh-funds` root asks the panel to read
  its funds again (`refresh_funds`) when the wallet changes, when the page comes
  back into view and after each press, as in ash-template. Existing Ethereum
  purchases still show and are still checked.
- The Credits admin and Purchase History print USDC to the millionth with at
  least two places ("5.00 USDC"). A purchase whose wallet no account holds yet
  reads "credited, waiting for an account" with "No account yet. These Credits
  wait until someone signs in with this wallet.", offers no Refund, and a refund
  refused for it says no account holds those Credits yet.
- The Points page's NFT tier read draws on the visitor's chain read budget, like
  Stake and Redeem; past it, the page says the NFTs could not be checked.

## 2026-10-11 — The five site-wide functions from ash-template (local, unreleased)

- On design-system `9faee245bad741a40e0dcd232dddb29e244b8c2e`. The header says
  "Sign in" and "Sign out". Account uses the shared signed-out, agents and
  Credits sections; Credits are read in the background and show loading, stale
  and error states. The motion kit matches the template (one figure-changed
  flash, count rolls keep decimals, Back and Forward reset the last input, the
  refusal shake stops with its message, the MotionRefusal hook is registered).
- A session that lapses while a page is open withdraws the account and the page
  says "Your session ended. Sign in again to see your account." on Account,
  Points, Purchase History and Credits admin, each through the shared
  signed-out section. Signed out, they say "Sign in to see your account."
- Autolaunch, the home page and /about say Memestock.
- decimal 3.1.2 in platform, agents, identity and payments (advisory
  EEF-CVE-2026-97853 on 3.1.1).
- Tests follow the 9 Oct shared staking reading: pages are seeded by running
  `Regents.Staking.SnapshotRefresh` and announcing its outcome as the listener
  does (`Regents.SharedStakingReading` in test support). The tests of the
  retired in-memory snapshot cache are removed, as is the Stake case for a
  reading with a missing seven-day window, which the refresh no longer saves.
  The contract, open-route, migration and release table lists include the
  9 Oct agent reads, `/capabilities`, `/agents.md`, `/skill.md`,
  `staking_protocol_readings` and `regent_agents.pairing_history`.

## 2026-10-11 — Live release merged, Points summary, agent budget read (local, unreleased)

- Merges the live release `ab6f1ffb` (Articles and its editor, Reading pages,
  the Research List on Daily Research) so the next release keeps them. The
  route catalog follows the router's order and the founder-shell handoff is
  regenerated.
- The Points page uses the shared Points summary (confirmed, earned today,
  activity being verified, daily allowances); the bonus and activity sections
  show once the figures are read.
- `GET /api/agent/v1/credits/budget` reads the paired agent's spending grant
  through `RegentCredits.agent_budget` and answers only the published fields
  (enabled, site_allowed, max_per_spend, daily_limit, sites, used_24h).
- elixir-utils pinned to `fd0719c3a1bcbb8906aea69302ede09d51b7e6ee` (shared
  budget read; Points period-end snapshots). The Points snapshot migration
  `20261009152652` is a shared-library migration and is not run by this site's
  release.

## 2026-10-11 — Review fixes on the Phase C candidate (local, unreleased)

- Paired agent reads check the pairing again just before the answer is sent.
  If the agent was unpaired or paired again while the read ran, the answer is
  replaced with `403 agent_not_paired`, so a former owner's data or pairing is
  never sent.
- The budget contract requires all six spending-grant fields in every copy
  (`contracts/api-contract.openapiv3.yaml`, `priv/static`, `priv/public/openapi.json`).
- `/blog`, `/blog/:slug` and `/blog/covers/:slug` are removed with nothing in
  their place (founder decision 3 a, 2026-10-08); the redirects re-added on
  10 Oct and their controller are gone.
- Redeem offers every wallet step once a token is chosen; the latest reading
  from Base only picks which one leads.
- Stake: when the REGENT allowance can't be read, Stake stays the main button
  and Approve REGENT is offered beside it. Approve leads only when Base shows
  the allowance is too small.

## 2026-10-11 — Second review fixes on the Phase C candidate (local, unreleased)

- Redeem offers both approvals as soon as a wallet is connected, before a token
  is chosen and while Base is still being read or could not be read; Redeem
  Animata joins them once a token ID is entered. The claim stays offered too.
- Each Redeem button, and the main Stake button, says "Confirming" only while
  its own step is waiting on Base.
- The API contract describes the paired agent refusal on all seven
  `/api/agent/v1` routes: `403` with code `agent_not_paired` or
  `person_not_here`, in every site copy.
- `blog/README.md` no longer says `/blog` redirects; `/articles` is the only address.

## 2026-10-11 — Test-only follow-ups to the third review (local, unreleased)

- The browser test server uses its own database (the test partition plus
  `_browser`), so the staking reading it saves no longer reaches `mix test`.
  It takes its one staking reading at start (`Regents.BrowserStakingReading`),
  so the Stake browser checks no longer depend on a reading left by an earlier run.
- The Redeem LiveView test for the no-token case checks only the steps the
  server builds; the browser check covers which buttons show.

## 2026-10-11 — Follow-ups to Sentinel's clearing of the Phase C candidate (local, unreleased)

- The header's Credits button, the Buy Credits panel with its Approve and Buy
  wallet buttons, and the Account page's Buy Credits button show whenever
  someone is signed in. While the balance loads, or when it can't be read, the
  header and the panel's figures show a dash (screen readers hear "Loading" or
  "Unavailable"), and the panel keeps its height. Before, all of them were
  hidden until the balance arrived, and for good after a failed read.
- The release step refuses to start until every migration in the pinned
  Credits and Points libraries is in that schema's own ledger (it names the
  missing ones), next to the existing agent pairing checks.
- The unused in-repo `agents/` and `payments/` copies are deleted with their
  `make check-agents` and `make check-payments` gates; the site already takes
  both libraries from elixir-utils.
- The release step checks the shared migrations first and names every missing
  version from both libraries in one message, then runs the agent pairing
  checks (fourth review).

## 2026-10-12 — Phase C candidate released

- regents.sh runs `b4b5e030` (the five 11 October entries before "Follow-ups to
  Sentinel's clearing"), released 12 October at 02:58 UTC. The follow-ups
  entry above it is still unreleased and goes out with the next shared-library
  update.

## 2026-10-12 — Shared-library update (local, unreleased)

- Pins elixir-utils `1f6ce01364ad3da8f0593f21a620e9fe1c199145` (an ENS
  redirect fix) and design-system `57d2f982a07dde733c0f1e05a7bd3b1a97cd58e1`.
  No new shared migrations.
- The Account page's Credits line and its Buy Credits, Purchase History and
  Points links sit inside the shared Credits box, which now takes them.
- The header and Buy Credits panel show Credits figures only from a balance
  just read; while it loads or can't be read, a dash.
- Buy is disabled only by a USDC or approval figure read since the last read
  began. A failed or still-running read never holds it back; the figure
  already shown stays on screen. Opening Buy Credits reads the wallet's funds
  again.
- The agent activity reader never follows a redirect, so its reader key goes
  only to the sign-in service.

## 2026-10-12 — Blue-green deploys (local, unreleased)

- Deploys start the new machine beside the old one, move traffic once
  `/healthz` answers, then stop the old one (Sean, 41 a, relayed by Sentinel).
  Error reporting needs no code change; it starts once `SENTRY_DSN` is set.

## 2026-10-12 — Sign-in re-checked before every update; wallet notes ask to switch

- An open page re-checks the sign-in before every update it receives and every
  background result, not only after a press. Wallet panels and the Credits
  panels do the same for their own results and act with the wallets the
  account links now. When the sign-in has ended, the update is dropped and the
  page shows that the sign-in ended.
- When the wallet app is on a wallet this account doesn't link, the note beside
  the buttons names it and asks to switch to the account's wallet; after a press
  it adds that nothing was sent. With no wallet open, it asks to open the
  account's wallet and press again.
- Buy Credits keeps showing the account's own wallet and its USDC while the
  wallet app is on another wallet. A figure read for one wallet never lands
  after the panel has moved to another.
- Browser agents' signed tools are built only from the tools that have their
  own signed inputs.
- `/developers` no longer redirects to `/docs`.
- Lists of cards on pages drawn once settle in the first time they scroll into
  view, not as the page opens.
- Correction to the entry above: error reporting needed code after all. Crashed
  processes and failed requests now reach Sentry through a logger handler, and
  each event leaves without its stack frames' arguments or a crashed process's
  state. Reporting still starts only once `SENTRY_DSN` is set.

## 2026-10-12 — Tests stay off the public Base node (local, unreleased)

- Buy Credits now reads the account's wallet as soon as a signed-in page opens,
  so tests that don't answer Base reads themselves sent them to the public
  node and timed out. Those reads are now refused in tests, and the Stake
  test helper waits the usual time again.

## 2026-10-12 — /developers keeps forwarding to /docs (Sean 58 a)

- The old regents.sh/developers link keeps sending visitors to /docs; the
  template pattern update had removed that forward.

## 2026-10-12 — Sign in always asks the wallet; Sign out always finishes Privy's logout (local, unreleased)

- Sign in on a signed-out page now logs out any Privy session the browser
  still remembers and always opens Privy's window, so someone who signed out
  and switched wallets comes back as the wallet they are on now, not the old
  one. The one-time recovery after a refused sign-in, and the server header
  that allowed it, are gone (template c8e9509).
- Sign out now logs Privy out on the page where it was pressed, waiting up to
  15 seconds. A logout that still could not finish is handed to the next page
  with the current time, and that page waits for it instead of cutting it
  short (template 69e454e and 4d698c7).

## 2026-10-12 — The sign-in check is never stored (local, unreleased)

- The page's "am I signed in?" check now tells browsers and proxies never to
  keep a copy, so a stale answer cannot be shown after signing in or out
  (template abfdac0).

## 2026-10-12 — Stake figures refresh without getting stuck (local, unreleased)

- A Stake refresh that crashes or runs out of time now tells open pages, the
  same as one that fails. Before, those pages kept waiting for a reading that
  was never coming.
- When the seven-day USDC figure can't be read, only that figure shows as
  unavailable. Every other contract figure still refreshes, and the deposit
  history catches up on the next pass. Before, one failed seven-day read
  stopped the whole refresh.
- Two checks now cover the refresh: one for a crash and one for a failed
  seven-day read.

## 2026-10-12 — Autolaunch picture says Memestock (local, unreleased)

- The Autolaunch picture on regents.sh/autolaunch now says "Memestock" in place
  of the old "Memestake", matching the page and the picture's own description.
  Only that word was redrawn, in the same font, size and colour.

## 2026-10-12 — Errors are kept on the site; Sentry removed (local, unreleased)

- Server faults in pages, requests and background jobs are now saved in
  Regents' own database and shown to Credits admins at regents.sh/admin/errors.
  Anyone else gets the ordinary not-found page.
- Only where each error happened is kept (the address, page or job); headers,
  query strings, form values and job details are dropped before saving.
  Mistakes a visitor can cause, such as a wrong address, are not saved. A
  resolved error is cleared after a week.
- Sentry is removed, so the SENTRY_DSN, SENTRY_RELEASE and SENTRY_ENVIRONMENT
  settings are no longer read.

## 2026-10-12 — Saved errors are cleared a week after they were last seen (local, unreleased)

- Once a day, every saved error that has not happened again for a week is
  cleared, whether or not anyone marked it resolved, along with any single
  occurrence older than a week. A fault that keeps happening stays visible.

## 2026-10-12 — Motion lab on the local site (local, unreleased)

- The motion lab at /animations shows every version of each movement side
  by side: presses, sliding panels, a rearranging list, rolling figures, a
  stamp, tabs, rising headlines and settling cards. It opens on a computer
  running the site locally, like the showcase, and not on regents.sh.
- The movements the real pages use match the shared kit: rising words are
  clipped by a class rather than a style, figures with units roll, and the
  lab's own presses answer for themselves.

## 2026-10-12 — Side panel in the header (local, unreleased)

- The account dropdown is gone. Signed in, the account name opens a side
  panel, and a panel button sits beside it in the header.
- The panel holds the account name, Account and Sign out, Pair your agent,
  and Help (Documentation, Agent guide, Contact). It closes with its own
  button or Escape, and stays open or closed as it was left, across pages
  and reloads.
- On the narrowest phones only the panel button shows in the header; the
  name is inside the panel.

## 2026-10-12 — Points page matches the shared template (local, unreleased)

- Until earning opens, "What earns points" names each way to earn with no
  amounts; the points tables, daily limits and NFT bonus tiers appear once
  earning opens. Earning itself is unchanged and still not open.
- While your points load, the page says so, and a failed reading says to try
  refreshing, instead of showing an empty card.
- The summary card is titled "Balance", and your NFT bonus shows as two
  lines: NFTs held and this period's bonus.

## 2026-10-12 — Buy Credits wording and close button (local, unreleased)

- The amount is labelled "USDC on Base", and the line under it says Regents
  Credits can be used across all Regents sites.
- The Buy Credits window's close button is full size again and stays in the
  top right corner while the window scrolls, the same as the template.

## 2026-10-12 — Daily Research: several papers a day (local, unreleased)

- A day on /paper-pro-daily may now hold several papers. Saving the same paper
  link on the same day again replaces it; a different link adds a paper.
- A day with two to four papers opens with one tile per paper (cover, title cut
  to 40 characters, authors when given); choosing a tile shows that paper below.
  Five or more wrap four to a row. Days with one paper look as before.
- Paper folders may list `authors`. Pictures are served by paper rather than by
  day, and the feed loads six days at a time.
- One migration in regents_app: the papers' one-a-day rule becomes one entry per
  paper link per day, and an empty-by-default authors list is added.

## 2026-10-12 — The template site in the agent spending list (local, unreleased)

- The account page's list of sites an agent may spend Credits on now includes
  template.regents.sh beside patchbay.help. Agent spending itself stays off.

## 2026-10-13 — Connect your agent at /start (local, unreleased)

- New page, regents.sh/start: one tab per agent (Hermes, Codex, Grok Bot, Muse,
  Dots, other agents), the steps to copy and give to it, and what happens next.
  Agents that ask for Markdown get the same steps for every agent at the same
  address. The page stays open while the launch gate is closed.
- The message the Account page gives an agent with its pairing code now points
  at that agent's tab on /start instead of llms.txt.
- llms.txt, agents.md and skill.md link /start and name regents-cli 1.9.3 with
  the commands that work today; the old npm command line note is gone.
- "Agent spending opens soon." replaces the paused-rollout wording on the
  Credits page and in agents.md.

## 2026-10-13 — Stake first, Credits in the menu, Keyfleet on /app (local, unreleased)

- /stake: the Stake box comes straight after the heading; the earnings figures
  sit beside it (below it on a phone). The opening line now reads "Earn a share
  of Regents Labs' USDC revenue, plus new REGENT." On a phone, Buy REGENT and
  View Chart share one row.
- The side menu gains "Credits" after Account. The Credits page is titled
  "Credits", with one line on what Credits are, and its list is "Purchases".
- /app lists Keyfleet beside the other products, with an Early access link to
  keyfleet.ai/early.
- On a phone, the home page shows the words and the products without the empty
  artwork box above them.
- /articles, before the first article, says one is on its way and points to
  Daily Research instead of showing nothing.

## 2026-10-13 — Agent steps for regents-cli 1.9.4, pairing from a file (local, unreleased)

- /start, agents.md, llms.txt, docs and skill.md give the template guide's
  steps with Regents' names: install regents-cli 1.9.4 exactly, check the
  version, sign in, run `regents protocol doctor`, check `agents whoami`, then
  pair.
- The pairing code never goes on a command line: the agent writes
  `~/pair.json` with its file tool, pairs with `< ~/pair.json`, then deletes
  the file. The same goes for the SIWA client steps (Grok Bot, Muse, Dots),
  which need the SIWA client 2.10 from siwa.regents.sh.
- agents.md follows the template's layout: install and sign in, check then
  pair, read for your person (each command beside its request), browser
  tools, Credits and Points.

## 2026-10-13 — Docs say only what is live (local, unreleased)

- /docs and llms.txt say /openapi.json covers every signed agent read, which
  it does, and that every operation in the YAML contract is live, instead of
  "retained product interfaces; some may not be available yet".
- /capabilities drops its "prepared_source" release labels: the tools are
  live and `account points` ships in regents-cli 1.9.4.

## 2026-10-13 — The sign-in server gets the body's digest, not the body (local, unreleased)

- elixir-utils moves to be6eeae. When regents.sh asks siwa.regents.sh to check
  a signed agent request, it now sends the digest of the request body instead
  of the body itself, so an agent's pairing code and page cursors never leave
  regents.sh. This goes live right after the sign-in server makes the same
  switch.

## 2026-10-13 — Each agent command says who may run it (local, unreleased)

- cli/commands.json names who may run each command instead of "wallet-proof":
  `agents pair` and `agents whoami` work for any signed-in agent; every other
  command needs an agent its person has paired with their account. None has
  extra conditions, since Regents lets no agent spend.
- `make check` now runs regents-cli's command check at 41da3144, the first
  commit that knows these names.

## 2026-10-13 — Articles moves below AI & SCIFI in the side menu (local, unreleased)

- Under Reading, the side menu now lists Daily Research, AI & SCIFI, then
  Articles (Sean, 13 Oct).
- Not a release: on 13 Oct 14:57Z nine of the twelve 13 Oct Daily Research
  papers moved to earlier days, three each to 9, 10 and 11 Oct, keeping the
  page's order (Sean, 13 Oct). Those days already had one paper each.

## 2026-10-13 — GitHub main's two unreleased changes join the release line (local, unreleased)

- Daily Research accepts ChatGPT's public message links
  (`https://chatgpt.com/s/t_…`) as well as share links
  (`https://chatgpt.com/share/…`) for a paper's ChatGPT link. This was
  committed to main on 13 Oct (e311cb05) but no release since has carried it.
- The Stake test for one approval per wallet keeps this line's wait for the
  second wallet's figures and gains main's check (8e9ab33b) that the second
  wallet still needs its own approval after the first wallet's is confirmed.

## 2026-10-13 — Confirm prompts show again (local, unreleased)

- Unpairing an agent on the Account page and locking Credits for a refund on
  the team's Credits page ask "are you sure?" before acting. Both prompts were
  written into the pages but never appeared, so one press acted at once: the
  page script did not load the part that shows them. It now loads it the same
  way the template does.

## 2026-10-13 — ENS pictures load (local, unreleased)

- A person's ENS picture is no longer lost when the ENS picture service is slow.
  The service takes one to five seconds to answer for a name it has not been
  asked about in the last hour, and the check gave up at two and recorded "no
  picture". It now waits ten seconds, and a service that does not answer in
  time changes nothing: the name and picture already held stay, and the next
  sign-in asks again.
- A name's picture is read only through the ENS picture service, never from an
  address the name's own record points at. This is how the shared library and
  the template read it.
- A picture service that answers "busy" or "broken" is treated the same as one
  that does not answer: nothing changes and the next sign-in asks again. Only
  its other answers, such as the one it gives for a name without a picture,
  mean no picture.

## 2026-10-14 — The $REGENT card sits still (local, unreleased)

- The "$REGENT / Stake in the work." card on the home page no longer leans
  toward the pointer. Its light still follows the pointer, as on the other
  cards on that page.

## 2026-10-14 — Keyfleet links open Keyfleet (local, unreleased)

- Keyfleet is open, and its early-access page now forwards to its home page.
  The Overview's Keyfleet card says "Club Keys come with a Regents Club Pass."
  in place of "Opens soon.", and its link is "Open Keyfleet".
- The Keyfleet page says "Club Keys come with a Regents Club Pass. Keys for
  sale open soon." and its second button is "See the Regents Club fleet", in
  place of "Tell me when it opens".

## 2026-10-14 — A refused picture read keeps the picture (local, unreleased)

- If the ENS picture service refuses this server's request, the name and
  picture already held stay and the next sign-in asks again. Before, a refusal
  was read as "no picture" and cleared a picture the account already had. Only
  the service's own answers about a name (none, a name it refuses, a redirect)
  mean no picture.

## 2026-10-14 — Credits are non-refundable (local, unreleased)

- The page at regents.sh/credits/refunds says Credits are non-refundable:
  Credits you bought, Credits you were given and Credits you received for an
  answer. The Regent team will consider an exception if you post in
  patchbay.help/credits-help, or write to support@regents.sh (Sean, 13 Oct).
- The team's Credits page no longer refuses a refund because the account has
  used Credits. The team decides each case.

## 2026-10-14 — Shared Credits and Points library moved (local, unreleased)

- An agent reading its person's Credits history gets one entry for each thing
  that happened: bought, gift, refund, set aside, returned, spent or received,
  with the amount, the site, and what led to a spend where the site kept it.
  Before, it got one line for each ledger transfer, with an operation code.
  The published description of that answer changed with it.
- The Points page names one daily limit shared by you and your agents, in
  place of one for you and one for your agents (Sean's rules of 13 Oct).
  Nothing new earns on Regents, and earning has not opened.
- Needs the shared Credits database change 20261013202732 (two new columns on
  holds) applied first; the release step refuses to go ahead without it.

## 2026-10-14 — Shared database changes are applied on their own (local, unreleased)

- A change to the Credits or Points database, which all five sites share, is
  now applied by its own team command ahead of a release, and the command
  prints what it applied or "none". A Regents release still only checks that
  nothing is missing and refuses to go ahead if something is. Since 11 October
  there had been no way to apply one in production at all.
- The team's "what is pending" command now also names any shared change still
  to be applied, without applying anything.

## 2026-10-14 — An agent's Credits history pages like every other read (local, unreleased)

- The answer an agent gets for its person's Credits history now carries
  `pagination.has_more` and `pagination.next_cursor`, the same paging keys as
  the template's other reads, in place of `more?` and `next`. Send
  `next_cursor` back unchanged as `after` for older entries.
- The command tool now offers "read the next page" on `account credits-history`.
- Same shape and same command entry as ash-template `41432ef` and `298c32a`.

## 2026-10-13 — The homepage hero is the world cube, on vgpu 0.6 (local, unreleased)

- The homepage is now a slowly turning cube with a room behind each
  of its six sides, one per world: Autolaunch, Techtree, Patchbay, Keyfleet,
  Regents staking and Regents on X. Drag to turn it, click a side to step into
  its room, and follow the room's link in a new tab. "Regents Labs" and its
  line stand over the top-left of the cube and step back while a room is open.
  The cube is the whole page between the header and the footer.
- Three panes of frosted glass hang in each room. Autolaunch, Techtree and
  Patchbay hang the titles and words of the three cards from the sections that
  used to sit further down the page. Keyfleet hangs three new ones (a Key is a seat, rooms
  for the work, notebooks the fleet keeps), Regents staking three in the words
  the staking page already uses, and Regents on X three past posts. A pane
  carries no link and no status words.
- The panes show one at a time for where the visitor looks: the first for a
  look to the left, the third for a look to the right, the second for a look up
  that is held for a moment. On a phone a tap looks where it lands. The room's
  name, line and link sit in a bar along the foot of the room for as long as
  the visitor is in it.
- The Patchbay room is a great hall: a switchboard filling the far wall with
  cords slung across it, rows of desks facing it, and a planet in the night
  beyond the glass above.
- Where the cube cannot be drawn, or for a visitor who asked for less motion,
  the six worlds are a plain list of cards with the same links.
- The cube is the one in ash-template, copied unchanged:
  `platform/assets/js/world_cube/`, the `WorldCube` hook and the
  `RegentsWeb.Components.WorldCube` component.
- Gone from the homepage: the glass crown and the picture behind it, the four
  product cards with their GitHub icons, the "Stake REGENT" button under the
  heading, the $REGENT panel with Buy REGENT, View Chart and Stake REGENT, the
  Autolaunch, Techtree, Patchbay and Keyfleet sections with their cards, and
  the closing "Explore staking" frame. The crown in the header and the Regents
  brand art are untouched. Staking stays one press away: Protocol and App in
  the header, and the Regents staking room in the cube.
- The Autolaunch, Techtree, Patchbay and Keyfleet tabs in the header now open
  that product's own site in a new tab, since the sections they used to scroll
  to are gone. Protocol still opens the staking page.
- `vgpu` moves from 0.3.1 to 0.6.0 and `@vgpu/wgsl` 0.6.0 is added.
- Removed with the crown: `platform/assets/js/home_prism/`,
  `platform/assets/js/home_field/` and the `HomePrism` hook, the four unit
  test files that tested them (`home_crown`, `home_palette`, `home_prism`,
  `home_scene`), and `platform/priv/static/images/home/hero-bg-dark.svg`. The
  browser checks now read the six worlds in place of the four cards, and the
  header check reads each product tab's site. The checks went with what they
  checked: the picture behind the hero being grey, the GitHub links on the
  cards, the crown being left out on a phone, the $REGENT panel and its
  buttons, each product section and its cards and statuses, a tab scrolling
  to its section, the closing frame and its white button.

## 2026-10-14 — The shared agents list and new button press (local, unreleased)

- Moves to design-system `92f9c69` (on `10a05c4`), the revision whose foil
  card runs on the cube's vgpu 0.6. The account's agents list
  is the shared one: each agent shows its picture, and "World ID Connected"
  with World's mark only when its person has connected World ID.
- Agent pictures now come from the shared package, staged by
  `mix regent_ui.assets` into `priv/static/images/regent-ui/`; Regents' own
  identical copies are gone.
- Buttons follow the shared look: a little give under a press, and white with
  Charcoal text in light mode.

## 2026-10-14 — Twin cubes on the homepage (local, unreleased)

- The homepage hero holds two cubes, copied from ash-template's twin cube page.
  The world cube moves into the left half; a code cube in the right half shows
  falling code on each face, a different colour and texture per face. "Human
  Browsing" and "Agentic WebMCP" appear above the two cubes while the pointer
  is on either one, and stay shown on touch screens. On a phone the code cube
  has its own stage under the world cube's.
- Each of the code cube's faces opens a card: the browser tools regents.sh,
  patchbay.help, techtree.sh, autolaunch.sh or keyfleet.ai offers on its home
  page, or how to connect an agent through siwa-server. The card scrolls and
  closes with its X or Escape. A room hides the code cube while it is open.
- Six new browser tools on the homepage open the same cards for an agent:
  `show_regents_webmcp_tools`, `show_patchbay_webmcp_tools`,
  `show_techtree_webmcp_tools`, `show_autolaunch_webmcp_tools`,
  `show_keyfleet_webmcp_tools` and `show_siwa_connection_help`, each also
  readable at `GET /api/v1/site-tools/<site>`. No sign-in; they change nothing.
- `Regents.SiteTools` reads each site's published tool list from its fixed
  address only (no redirects, 3 s to connect, 5 s to answer) and keeps it for
  a day, or a minute after a failed read. Only one read of a site is ever
  under way; requests that arrive meanwhile wait for its answer, so a burst of
  visitors asks each site once. A read still under way after 10 seconds is
  stopped and counts as a failed one. The page asks in the background, so a
  slow site never holds the homepage. The address is described in
  `/openapi.json` with its `site_not_found` (404) and `site_unreachable` (503)
  answers.
- The world cube takes `--world-cube-size` beside `--world-cube-centre`, and
  the code cube `--code-cube-size`, so a page can draw either smaller. The
  stage keeps the same height whether or not the cubes draw.

## 2026-10-14 — A picture for each agent (local, unreleased)

- A person can give each of their agents a picture on /account, in the agent's
  window: a PNG, JPEG or WebP of up to 5 MB, previewed as the square it will
  be, then saved, changed or removed. It is shown beside what the agent posts
  on every Regent site.
- Each upload is re-made as a 256 × 256 WebP cut from the middle, carrying
  nothing else the file held (`Regents.AgentPicture`, on Vix 0.42.0, the
  version Keyfleet runs). A file that is not a whole picture, is over 5 MB or
  100 million pixels, or still over 64 KB once made is refused with a reason.
- `GET /agents/:wallet/picture` serves it to anyone as WebP. A link carrying
  the picture's current `?v=` is kept for a year; any other is checked each
  time, so a changed or removed picture is never shown from an old copy.
- The team may remove a picture, and only remove one, under "Agent pictures"
  on /admin/credits. The team is the `REGENT_CREDITS_ADMINS` list, now read by
  both the Credits and Agents libraries.
- The library side, `regent_agents.agent_pictures` (migration
  `20261014150000_agent_pictures`) and a message to every site when a picture
  changes, comes with the elixir-utils move in the Ash 3.36 entry below.
- `/app/bin/migrate-shared` and `/app/bin/pending-migrations` now cover the
  shared Agents changes as well as Credits and Points, and a deployment refuses
  while one is missing. Production's Agents ledger held all four earlier
  versions on 14 October, so this check replaces the separate pairing-history
  check.

Before release:

- elixir-utils `c2c24cc` must be on GitHub, and its picture table applied to
  the shared database with `/app/bin/migrate-shared` from the new image, on the
  founder's own named go, before this deploys.

## 2026-10-14 — Ash 3.36, and Points hears about Credits itself (local, unreleased)

- Ash 3.36.0 and AshOban 0.10.0, as ash-template runs them (Oban 2.24.2,
  Sourceror 1.12.4 with them; nothing else moves).
- Moves elixir-utils to `c2c24cc`: the Ash 3.36 line and agent pictures.
- Credits now announces a credited or newly held purchase as a signal, and
  the new `Regents.Points.Award` listens for it and offers Points
  `credits.purchase_settled` in the same transaction. This replaces
  `Regents.Credits.Credited` and the `on_credited` setting, which are removed.
- `mix check` allows one more compile-time link (38), for the new Points
  domain's link to its resource, like every other domain.

Before release:

- ash-template's own Ash 3.36 release live and healthy first.
- elixir-utils `c2c24cc` on GitHub (it carries agent pictures, so the picture
  table steps above apply to this release).

## 2026-10-14 — The Points list Sean set (local, unreleased)

- Moves elixir-utils to `72849c1`, the Points list Sean set on 14 October:
  "First paired agent" is worth 25; the profile, email, first-agent-connected,
  ERC-8004 listing and Patchbay solution awards are gone, 335 in one-time
  awards. A Patchbay Offer placed earns 5 (up to 10 a day) and a reply 5 (once
  a day). Points has not started, so nothing earns yet. No database change.

## 2026-10-14 — Copy the WebMCP tools as Markdown (local, unreleased)

- The code cube on the homepage shows "Copy all WebMCP Tools as Markdown"
  while the pointer is on it and for two seconds after it leaves (always on a
  touch screen). It copies every site's tools, one section for each of
  regents.sh, patchbay.help, techtree.sh, autolaunch.sh, keyfleet.ai and the
  siwa-server connection steps. The page reads the five sites once it is live
  and does not keep the copy after sending it.
- Each face's window has "Copy text as Markdown" for what that window lists.
  The button's space is held while the list is read.

## 2026-10-14 — A balanced homepage footer (local, unreleased)

- The homepage footer copies ash-template `6a5896a`: site links on the left,
  X and GitHub centred, © on the right, all on one line, with larger text
  and icons; stacked and centred on a phone. On a phone the code cube's copy
  button sits under "Agentic WebMCP" so the two never overlap.

## 2026-10-16 — Regents Products

- The menu behind the footer's nine dots is now headed "Regents Products", and
  its button says the same, as in ash-template `fadd0f7` (Sean, 16 Oct; it was
  "Regents Labs apps").

## 2026-10-16 — Regents v190 (main `ee99f43d`)

Released on Sean's "1. a" (RG-DEPS-W1-REL, 13:27Z), after Sentinel's GO on
`b8f97b4d..ee99f43d`. No database migrations. Rollback is v189 (`b8f97b4d`).

- Dependency wave 1: Bandit 1.13.1 from Hex (with the CVE-2026-105659 fix),
  Ash 3.36.1, AshOban 0.10.1, Thousand Island 1.6.0, Privy react-auth 3.49.1,
  and test-tool patches.
- elixir-utils `97cc964`: an agent check-in is refused when this site has no
  account for the person, and a refused check-in leaves last contact as it was.
- The side panel pairs agents. On a wide screen it sits beside the page; on a
  narrow one it slides in over the page and opens only when opened there. It
  takes focus on opening, and Escape closes it. The Account page has its own
  pairing box, so the side panel leaves that out there.
- Pairing offers only the agents the shared library allows.
- One footer for the home page, public pages and the app: Developer docs,
  Agent guide, Privacy policy and Terms of use. Regents Products moves to the
  top bar and lists products only. Agents see the number of WebMCP tools, with
  a list that copies as Markdown.
- Deploys use `make deploy`, which labels the image with the commit it was
  built from.

## 2026-10-16 — Regents v191 (main `ec0f2094`)

Released on Sean's "3. a" (16:12Z), after Sentinel's GO on `ee99f43d..ec0f2094`
(16:01Z). Protected: the agent check-in path. No database migrations. Rollback is
v190 (`ee99f43d`). The held quarter-second Stake check (`ea078901`) is not in it.

- An agent whose person has not signed in on this site gets `person_not_here`,
  with a hint to ask their person to sign in and pair it, in the check-in answer,
  `/me`, the contract, openapi.json, docs.md and llms.md.
- Agent guides name regents-cli 1.10.12.
- Shared buttons from design-system `9e93f14` and elixir-utils `a8b8358`, with
  their motion. External links say they open in a new tab to screen readers.
- The home bar fits on one row from 1280 px.
- Stake: "Stake for a different address" sits beside Amount, and the receiving
  address and its warning open under Amount, above the Stake button. The panel
  keeps the same height in Stake and Unstake. The rewards heading reads "Claim or
  compound rewards". 50% and Max lose the arrow.

## 2026-10-16 — Regents v192 (main `3c816f79`): agent wording, narrow-screen layout and homepage buttons

Live as Fly v192 at 19:42Z after Sentinel's GO on `ec0f2094..3c816f79` (19:37Z),
and deployed again as Fly v193 at 20:44Z on Sean's "1. a" (20:38Z), the same
image. Covers this entry and "Homepage button refinement" below. No protected
area and no database migrations. Rollback is v191 (`ec0f2094`). The held
quarter-second Stake check is not in it.

- Agents read "this site", never "this website" or "/account". `person_not_here`
  says: "Ask your person to sign in on this site once, then send the request
  again." `agent_not_paired` points at Pair your agent in the side panel, on any
  page of this site. The 403 description, the contract copies and openapi.json
  say the same, and cli/COMMANDS.md names the side panel.
- On a phone the header shows the crown alone, as the template does; the link
  keeps the name for screen readers. Buy REGENT and View chart keep one line.
- The home bar keeps one row from 1232 px, with tighter gaps just under 1280.
- Stake: Unstake opens no gap between Amount and the button. When the panel is
  too narrow for the button beside 50% and Max (phones, and 1100–1240 px), the
  button takes the whole row with Available and the shortcuts below it. "Unstake
  REGENT" keeps one line, so both modes have the same height.

## 2026-10-16 — Homepage button refinement

Approved by Sean for push and deployment after reviewing the local preview.
No database migrations or changes to sign-in, staking or wallet behavior.

- Product links use equal spacing and padding, a quieter fill and a fine outline.
- The existing VGPU foil follows the pointer and brightens on press; the shared
  Anime.js press moves the paint and label while the clickable area stays fixed.
- Narrow screens preserve label padding; keyboard focus remains clear, and
  reduced-motion and forced-color settings suppress the foil.
- The homepage App button no longer has an arrow.

## 2026-10-16 — Regents v194 (main `01a9f9ac`): side panel agents and Pair New Agent

Released as Fly v194 at 20:51Z on Sean's "4. a" (20:38Z), after Sentinel's GO on
`6c0474df`, its delta reads of `40695b94` and `01a9f9ac`, and elixir-utils
`03433b80`. Protected: sign-in area and agent pairing. Rollback is Fly v193
(`3c816f79`). The held quarter-second Stake check is not in it. Live walk headless
signed out at 390 and 1440 px: /, /stake and /start load with no page errors and
no sideways spill, and /start's Pair New Agent lands on /account.

Ported from ash-template v96 (f36a9da4) and v98's 8c33273, with the shared library
at elixir-utils 03433b80 and design-system 28888839 (which holds the template's
df44fc34).
No database migrations. Needs `SIWA_ACTIVITY_READ_TOKEN`, already set on regents-sh-web.

- The side panel lists the signed-in person's agents, each with the site it was
  last active on ("Active on Patchbay", with how long ago), read again each time
  the panel opens. Below them, Pair New Agent holds the one pairing box: the
  message to paste first, with icons to copy it and make a new code, then ten
  agents to choose from by their pictures.
- The panel's head has Sign out and Manage Account. The panel's own close button
  is gone; the header's panel button opens and closes it, and on narrower screens
  the panel now opens below the header so that button stays in reach.
- The Account page's agents list has a Pair New Agent button that opens the
  panel, in place of a second pairing box.
- An agent's details show where it was active across the Regent sites, a line for
  each site and day with its first and last request, kept for 30 days. Readings
  are kept on the machine for five minutes (`Regents.Agents.ActivityReading`),
  replacing `Regents.AgentActivity` and its own sign-in service settings.
- Agents told to pair are sent to Pair New Agent in the side panel: the
  agent_not_paired hint, the API description, agents.md, llms.md, docs.md, the
  /start page and prompts, the site tools, cli/COMMANDS.md and cli/commands.json.
  The /start page's first step has a Pair New Agent link that opens the panel.
- An agent's sites include the Regents mobile app (elixir-utils 583e2c60), so its
  days there are no longer left out.
- A day from the sign-in service with a missing field or an unreadable value makes
  that agent's reading `{:error, :bad_day}` instead of raising (elixir-utils
  03433b80), and the panel reads each agent through
  `Task.Supervisor.async_stream_nolink` under `Regents.Agents.Reads`, so a reading
  that still crashes ends only itself and leaves that agent's line empty, never the
  page (Sentinel's v193 finding F2).
- An open pill menu closes on Escape or a tap outside it, iPhones included.

## 2026-10-16 — Regents v195 (main `73c6a9ce`): quarter-second Stake check and Articles out of the left menu

Previous release: Fly v194 (`01a9f9ac`). No database migrations.

- After a wallet step on the Stake page is sent, the page checks Base for it every
  quarter second (was every two seconds), up to 90 checks or until the step
  settles, one loop per step, as the template does (template `9b728cb`). What the
  step sends, its amounts and who signs it are unchanged (`e6ab2e8c`, Sean's
  "2. a", Sentinel GO).
- The left menu's Reading group ends at AI & SCIFI; Articles is no longer listed
  there. Articles, each article and the Articles editor still open by link
  (`73c6a9ce`, Sean: "remove the articles left sidenav button").

## 2026-10-16 — Share pictures for the home page, Paper Pro Daily, Stake and Redeem

Not yet released. No database migrations. No change to how Stake or Redeem work.

- The home page, Paper Pro Daily, Stake and Redeem each share their own 1200×630
  picture on X and other sites, in `priv/static/images/share/`, instead of the
  1024×512 crown. Each picture shows the page's headline and purpose in the
  platform look: cut corners, a Tangerine and a Powder Blue corner mark, the Geist
  fonts, and a small version of the page's own pictures (the six site tiles, three
  recent paper first pages, the Animata artwork). Sean's X post of Paper Pro Daily
  showed a blank grey card.
- Each picture has its own alt text, and its address is fingerprinted through
  `Endpoint.static_path`, so X fetches it fresh. Every other page still shares the
  crown, and `/literature` keeps its chart picture.

## 2026-10-16 — Regents v195 released; v196 candidate: share pictures and the /stake Safari fix

- Fly v195 (main `0d236015`) went live at 21:25Z on Sean's "1. a" (21:22Z);
  rollback Fly v194 (`01a9f9ac`).
- v196 pins design-system `f9b0e25`: /stake no longer crashes Safari/WebKit (the
  ratio card's badge border is one colour mix instead of a nested one). Same
  colours; Chromium shows no pixel change (`62d94044`, Sentinel GO).
- v196 also carries the share pictures for the home page, Paper Pro Daily, Stake
  and Redeem described in the entry above.

## 2026-10-16 — v196 candidate: agents are told to pair in the side panel

- An unpaired agent's hint now reads exactly "Ask your person to sign in on this
  site and pair you with Pair New Agent in the side panel, then send the request
  again.", the template's new wording. agents.md, llms.md, docs.md, the agent
  guide, the API contract copies, cli/COMMANDS.md and cli/commands.json no longer
  say "on any page", since some pages have no side panel.

## 2026-10-17 — The nine-dot button's icon is centred

- The top bar's nine-dot button (Regents Products) and the side panel button showed
  their icon about 11 pixels left of centre: the header's shared cell rule made them
  flex boxes without centring. `#app-shell #shell-header .shell-tool` now centres
  them (Sean, 16 Oct, with a screenshot: "the 9 dots icon, specifically on
  regents.sh and maybe elsewhere, looks wrong"). The other Regent sites were
  measured and are already centred.

## 2026-10-17 — Regents v196 released; v197 candidate: agents' activity reads during an outage

- v196 (`b8988ea9`) went live as Fly v196 at 01:21Z on Sean's go, with v195
  (`0d236015`) as the rollback. All four share pictures (home, Paper Pro Daily,
  Stake, Redeem) answer 200, and the signed-out walk of /, /stake and /start at
  390 and 1440 px showed no overflow and no page errors. The empty platform-phx
  Fly app was deleted on Sean's go.
- Agents' activity in the side panel and on the Account page now keeps a failed
  read from the sign-in service for one minute, so while that service is down each
  agent is asked again at most once a minute, however often the panel opens
  (template `ea1105e`). Each read that gives no reading is counted by reason in
  `health.agent_activity_unread.total` (template `ca82af6`). elixir-utils moves to
  `72ccfea`, which names an answer without a list of days `:bad_days`. The panel's
  crash-proof reads (template `449e71a`) were already here.

## 2026-10-17 — v197 candidate: "not paired" says what it means

- The agent guides (agents.md, llms.md, docs.md and the guide at /agents/start)
  said a `not_paired` refusal meant the person had unpaired the agent. It also
  covers an agent that was never paired, so they now say the agent isn't paired
  with its person on this site, the wording Sentinel ruled for the template's
  troubleshooting line on 16 Oct.

## 2026-10-17 — Regents v197 released; v198 candidate: the Stake page's opening line

- v197 (`0604ce9a`) went live as Fly v197 at 01:50Z on Sean's go after Sentinel's
  GO, with v196 (`b8988ea9`) as the rollback. Sentinel's after-read was healthy:
  no 5xx, the new not_paired wording live on every agent guide, and the header
  icon 0.5 px off centre.
- /stake's opening line now reads "Staked $REGENT earns your share of USDC revenue
  from all products." in place of "Earn a share of Regents Labs' USDC revenue, plus
  new REGENT." (Sean, 17 Oct, word for word).

## 2026-10-17 — Account page: panels in a sensible order

- /account put the account card, then the wallet details alone in a narrow
  column with empty space beside it, then the agents, then Credits beside the
  names panels with large gaps under the shorter ones. Now the account card and
  Agents run full width at the top; below them, on a wide screen, Credits,
  Claimed Regent Names and Claim a Regent Name stack in the left column, and the
  wallet details, verified connections and sign-out stack in the right one. Each
  column stacks its own panels, so a tall panel never leaves a gap beside it. A
  phone shows one column in that same order (Sean, 17 Oct).

## 2026-10-17 — Stake page: pro rata line and a 20% Yield badge

- /stake's opening line now reads "Stake to earn a pro rata split of all Regents
  Labs' USDC revenue." Under it, an orange badge reads "Temporary 20% Yield for
  early community" (Sean, 17 Oct 15:44Z). This replaces the earlier v198 line,
  which never went live.

## 2026-10-17 — Staking described the same way everywhere

- The home page's staking summary, the Stake link preview text, its share
  picture and alt text, and the opening of about.md now match the Stake page:
  stake to earn a pro rata split of all Regents Labs' USDC revenue, plus a
  temporary REGENT yield for the early community (the share picture says "Early
  20% yield"). They said "new REGENT" or "emissions" before (Sean, 17 Oct
  16:04Z, decision 4. a). The detailed notes in about.md on how the REGENT rate
  works are unchanged.

## 2026-10-18 — Regents v198 released

- v198 (`9c875a9e`) went live as Fly v198 at 02:37Z on Sean's go ("ok go ahead
  to push", 18 Oct 02:33Z, after his yes to decisions 3 and 4) without a
  Sentinel pre-read, which had not arrived. The rollback is v197 (`0604ce9a`). It
  carries the /account panel order, the Stake page's pro rata line and 20% Yield
  badge, and the matching staking wording on the home page, link preview, share
  picture and about.md. Live checks: the deployed image is labelled `9c875a9e`;
  /, /stake and /account answer 200 at 390 and 1440 px with no overflow or page
  errors; the new share picture is served.

## 2026-10-18 — Home page: the staking card is called "Staking"

- The home page's staking card and its button now say "Staking" and "Visit
  Staking" instead of "Regents staking". Where the cube is not drawn and the six
  cards sit in three columns, "Visit Regents staking" was the one button that
  took two lines between about 1000 and 1240 px wide, and at 768 px its name ran
  past the button's edge (Sentinel's v192 read). Now it matches the other five.

## 2026-10-18 — Base reads wait once when the provider is busy

- When the Base read provider answers "too many requests", the site now waits
  the pause the provider asks for (at most two seconds) and asks once more,
  instead of showing the figures as unavailable straight away. Every refused
  read is now written to the log with its status, so a busy or failing
  provider shows up in the logs (Sentinel, v195 read).

## 2026-10-18 — Regents v199 released

- v199 (`17315589`) went live as Fly v199 at about 17:33Z on Sentinel's GO
  (ordinary, 17:29Z), under the standing release permission. The rollback is
  v198 (`9c875a9e`). It carries the home page's "Staking" card name. Live
  checks: the deployed image is labelled `17315589`; /healthz answers 200; /,
  /stake and /account answer 200 at 390 and 1440 px with no overflow or page
  errors; the six "Visit" buttons fit at 320 to 1440 px with none spilling.

## 2026-10-18 — Home page: the site buttons fit beside the heading

- Between 768 and 895 px wide, where the six site buttons (regents.sh,
  patchbay.help and the rest) sit beside the heading, they now go two to a row
  instead of three, so "patchbay.help" and "autolaunch.sh" are no longer cut off
  by 14 px and "siwa-server" stays on one line (Sentinel's v199 read). From
  896 px they go three to a row as before.

## 2026-10-18 — Correction to the v199 release record

- The v199 record says the six "Visit" buttons "fit at 320 to 1440 px". More
  exactly: none spills past its edge, but between 768 and about 1000 px, where
  the cards sit three to a row, every button wraps its name onto a second line
  inside the button (Sentinel's v199 after-read). That wrap comes from the shared
  world cube layout and is with the template owner.

## 2026-10-18 — Regents v200 released

- v200 (`399988a6`) went live as Fly v200 at about 17:44Z on Sentinel's GO
  (ordinary), under the standing release permission. The rollback is v199
  (`17315589`). It carries `351d8338`, "Base reads wait once when the provider
  is busy". Live checks: the deployed image is labelled
  `399988a6813d551bee881ea8cbe85b2b03b97864`; /healthz answers 200; /, /stake and
  /account answer 200 at 390 and 1440 px with no overflow or page errors; the
  logs since the release show no refused or retried Base reads.

## 2026-10-18 — Base reads: a garbled "wait" from the provider is ignored

- When the Base read provider says "too many requests" with a pause the site
  cannot read (a fraction of a second such as "1.5", a word, or two pauses at
  once), the site now waits one second and asks once more, as it does when no
  pause is given. Before, that read was logged as a broken connection instead
  of a busy provider (Sentinel's v200 pre-read).

## 2026-10-18 — Regents v201 released

- v201 (`290e02af`) went live as Fly v201 at about 18:03Z on Sentinel's GO
  (ordinary, 18:00Z), under the standing release permission. The rollback is
  v200 (`399988a6`). It carries four commits:
  - `180c0834`: between 768 and 895 px wide the hero's six site buttons go two
    to a row, so none is cut off ("Home page: the site buttons fit beside the
    heading").
  - `c5eab96f`: the correction to the v199 record on the "Visit" buttons. It
    changes this file only.
  - `4ea56a73`: the v200 release record. It changes this file only.
  - `290e02af`: a "wait" from the Base read provider that the site cannot read
    is ignored and the one retry waits a second ("Base reads: a garbled 'wait'
    from the provider is ignored"). It changes the Base read client only.
- Live checks: the deployed image is labelled
  `290e02af40832b2b29ad94dcee01620b14dd1068`; /healthz answers 200; /, /stake and
  /account answer 200 at 390 and 1440 px with no overflow or page errors; on the
  live home page the six site buttons are cut off nowhere from 390 to 1440 px.
  At 320 px two of them ("patchbay.help" and "autolaunch.sh") are still 1 px too
  narrow for their names, as before this release; that comes from the button
  spacing shared with the other sites and is with the template owner.

## 2026-10-18 — Redeem and the gallery: owned-NFT lookups are shared fairly

- Looking up which NFTs a wallet owns uses the site's one OpenSea allowance,
  which every visitor shares. Each visitor could start six lookups a minute
  for every page they had open, so one person with many tabs could use the
  whole allowance and leave "Owned NFT lookup is unavailable" for everyone
  else. The six a minute now count once per visitor across all their pages.
  Past them, the page shows the lookup as unavailable and the collection and
  token ID fields stay open, as before (security review follow-up, 7 Oct).

## 2026-10-18 — Regents v202 released

- v202 (`b14705c7`) went live as Fly v202 at about 18:30Z on Sentinel's GO
  (ordinary, 18:23Z), under the standing release permission. The rollback is
  v201 (`290e02af`). It carries `b14705c7`, "Redeem and the gallery: owned-NFT
  lookups are shared fairly": the six OpenSea lookups a minute now count once
  per visitor across all their pages instead of once per page.
- Live checks: the deployed image is labelled
  `b14705c7ca8282f2d72caf7e90d6132e75ad829b`; /healthz answers 200; /, /stake and
  /account answer 200 at 390 and 1440 px with no overflow or page errors;
  /redeem and /redeem/gallery answer 200. The platform README now says that
  visitors who share one network address share one allowance (Sentinel's
  v202 read).

## 2026-10-18 — Stake: ticking "Stake for a different address" keeps the panel's height

- Ticking "Stake for a different address" used to grow or shrink the Stake
  panel: the address box and its warning appeared, and the lines under the
  button came and went while the address was not ready yet. The panel now keeps
  one height whatever the box shows (Sean's 5. a, under the "choices never
  change the height" rule). Rows the current choice does not use keep their
  room, unseen, at the foot of the form: the address box and its note while the
  box is unticked or Unstake is open, and the position preview and the lines a
  stake of your own would show while it is ticked. The invalid-address message
  and the warning share one slot the size of the warning, and the address in
  the warning is in fixed-width letters so every address takes the same room.
- Layout only: the button, the amounts and the wallet steps are unchanged.
  Measured signed in at 1280, 390 and 320 px: unticked, ticked, an invalid
  address, four valid addresses, the warning acknowledged, and both tabs all
  give the same panel height at each amount.

## 2026-10-18 — Regents v203 released

- v203 (`b40dbded`) went live as Fly v203 at about 22:40Z on Sentinel's
  protected GO (20:42Z) and Sean's "1, a" (22:35Z) naming `b40dbded`. The
  rollback is v202 (`b14705c7`). It carries `b40dbded`, "Stake: ticking 'Stake
  for a different address' keeps the panel's height".
- Correction to the entry above: the Stake tab keeps one height in every state,
  but the Unstake tab has its own, shorter height (1203 px against 1437 px at
  1280 px). Holding one height leaves blank room above "Claim or compound
  rewards": 219 px at 1280 and 262 px at 390 in the default view, 264 px and
  392 px with another address entered (it was 0–30 px before).
- Live checks: the deployed image is labelled
  `b40dbded531c08f03fc73b418429f7137055be88`; /healthz answers 200; /, /stake,
  /account, /redeem and /redeem/gallery answer 200 at 390, 1280 and 1440 px with
  no overflow or page errors. The signed-in Stake panel cannot be measured on the
  live site without a wallet; its heights were measured signed in on `b40dbded`
  locally and by Sentinel at eight widths.

## 2026-10-18 — Home page code cube: a side copies its text; View Tools opens it

- A click on a side of the code cube now copies that side's text as Markdown
  and says so in a note by the pointer that fades away: "patchbay.help WebMCP
  tool text copied" for a site, "quickstart text for agent copied" for
  siwa-server (Sean, 18 Oct 23:05Z). Every click copies again. A site still
  being read says "Reading patchbay.help's tools…" and copies nothing.
- The tools window now opens from a "View Tools" button. Beside the drawn cube
  it sits at the cube's top right for the side the pointer rests on, stays two
  seconds after the pointer leaves so it can be reached, and shows after a tap
  on a phone. Where the cube is six buttons, each has its own View Tools in its
  top right, shown on hover or keyboard focus, and always on a touch screen.
- The hint under the cube reads "Drag to turn. Click a side to copy its tools."
  On a phone the "Human Browsing" and "Agentic WebMCP" names sit at the left of
  their stages, clear of View Tools.
- The page's own WebMCP tools still open the same window, now by pressing the
  side's View Tools.
- On a touch screen each View Tools is finger-sized, with a strip of its side
  below it to press for the copy. On the narrowest phones the longest names
  keep inside their buttons, and on a computer View Tools no longer touches
  the name below it.

## 2026-10-19 — Stake for a different address opens a window

- Ticking "Stake for a different address" on /stake opens a small window for
  the receiving address and its warning. Done or Escape closes it.
- The row beside "Amount" then says where the rewards go: "Rewards go to" and
  the short address with Change, or "No address yet" with Add until the address
  is valid and its warning ticked. Unticking stakes for yourself again.
- A stake of your own no longer leaves a blank band below the form. A stake for
  someone else keeps the room of the position preview, so the panel keeps one
  height.
- On the narrowest phones the choice takes its own row under "Amount". The box
  and Change are each a full finger's press.

## 2026-10-19 — Stake: what is available stays readable on small phones

- On the narrowest phones "Available" sat under the 50% and Max buttons. It now
  keeps its row, and the two buttons move below it when both do not fit; on
  wider screens they still sit beside it.

## 2026-10-19 — Stake: the different-address choice keeps normal size on a computer

- On a computer, "Stake for a different address" and its Add or Change link
  are the size of their words again, so the row no longer looks blocky. On a
  touch screen each still takes a full finger's press.

## 2026-10-19 — The home page keeps one cube

- The home page now shows one cube, with "Human Browsing" over it. On a
  computer it is about half again as big as before.
- The "Agents see" window has a new button, "Copy all Regents WebMCP tools",
  which copies every Regent site's tools at once, each site in its own
  section, then how an agent signs in. The line under it says how many tools
  it found.
- Agents get a tool for each site's full list of tools, and one tool for the
  complete list of every site.
- The window no longer shuts by itself when it is opened while the page is
  still loading.
- The cube now stands in the middle of the page on a computer, with "Human
  Browsing" above it and the hint under it. On mid-size screens it is drawn a
  little smaller so it sits under the heading instead of across it.

## 2026-10-19 — Regents v205 and v206 released

- v205 (`0f993b76`, the Stake fixes) went live as Fly v205 at about 13:58Z, then
  v206 (`9df1d931`, the one-cube home page, which contains `0f993b76`) as Fly
  v206 at about 14:03Z, on Sean's "1. a" (13:53Z) to deploy on this thread's own
  fresh-copy checks. The rollback for both is v204 (`f76843f9`). No migrations.
- v205 carries `2fcfbf67`, `4ef219bb`, `2410c77a`, `6b3a757f`, `807a94b0`,
  `b4d90922` and `0f993b76`. v206 adds `485275b7` and `9df1d931`.
- Live checks after v205: the image is labelled
  `0f993b76ad3564c645b7b78dca06622fd12b8ad5`; /healthz answers 200; /, /stake,
  /account, /redeem and /redeem/gallery answer 200 at 320, 390, 1280 and 1440
  in headless Chromium with no page errors and no sideways scroll. The signed-in
  Stake form was not walked live (it needs a real sign-in).
- Live checks after v206: the image is labelled
  `9df1d9314ec4bf98baaf4e01d15c58c671c949cf`; the same pages answer 200 with no
  errors or sideways scroll; one cube draws at 1920 to 390 with "Human
  Browsing" shown; the tools window opens at 1440 and 390 with "Copy all Regents
  WebMCP tools" and 166 tools from 5 sites; /api/v1/site-tools lists no site as
  unreachable.

## 2026-10-19 — Public reading and profile reads for agents

- Agents and the command line can now read what anyone can already read on the
  site, with no sign-in, pairing or wallet: the list of published papers and one
  paper with its full write-up, the list of Articles and one Article in full, the
  AI & SCIFI book list, and one public Regent profile by its address name.
- New routes: `/api/v1/reading/papers`, `/api/v1/reading/papers/{id}`,
  `/api/v1/reading/articles`, `/api/v1/reading/articles/{slug}`,
  `/api/v1/reading/literature` and `/api/v1/regents/{slug}`. Lists page with an
  `after` cursor taken unchanged from the previous answer. Drafts and future-dated
  posts stay hidden, as on the pages.
- New WebMCP tools: `regents_research_list`, `regents_research_paper`,
  `regents_articles_list`, `regents_article`, `regents_literature` and
  `regents_public_profile`.
- Cover pictures in these answers carry the record's last-change time, so an
  updated cover is never served from an old copy.
- Restacked from the parked agent branch (`0271906c`, `a56a6c65`, `4116c36e`)
  onto the live code; the other parked commits wait on the template or on Sean.

## 2026-10-19 — Regents v207 released

- v207 (`2986ceed`, public reading and profile reads for agents) went live as
  Fly v207 at about 18:14Z under the standing permission for ordinary releases.
  The rollback is v206 (`9df1d931`). No migrations.
- Before release, a fresh copy of `2986ceed` succeeded: 551 server tests, 232
  script tests, the browser suite (102) on port 4002 and again on 4123, the CLI
  command check and the identity check; both deliberate breaks (drafts shown,
  a private profile field added) were caught; the copy stayed clean. The shared
  library check only runs in a real checkout, where it succeeded on the same
  content. Evidence: `control/coordination/evidence/regents-sh-2986ceed-*`.
- Live checks: the image is labelled
  `2986ceed951732205077c92bb16baa91258d03a0`; /healthz answers ok; the paper,
  Article and book reads answer 200, the second paper page follows the cursor,
  covers load, an unknown profile answers 404 and an unknown query answers 400;
  the six new tools appear in /api/v1/site-tools; /, /stake, /account, /redeem,
  /paper-pro-daily, /articles and /literature answer 200 at 390 and 1280 in
  headless Chromium with no page errors and no sideways scroll.

## 2026-10-19 — Agent answers match the template

- The agent pair and check-in answers have always carried the pairing `id`; the
  published contract now lists it, as ash-template's does. Redone from the
  parked commit `e7c76b08`.
- A Credits history cursor that is not valid now answers 422 `invalid_cursor`
  with the template's words ("That history cursor is invalid."), instead of 400.
  Other failures still answer 503. Redone from the parked commit `5e7ae9df`, with
  the docs, CLI descriptions and tool text in plain words.
- Two checks cover these: the pair and check-in answers name the same pairing
  id, and a bad cursor gets the 422 refusal.

## 2026-10-19 — Regents v208 released

- v208 (`9626247b`, agent answers match the template) went live as Fly v208 at
  about 18:35Z under the standing permission for ordinary releases. The rollback
  is v207 (`2986ceed`). No migrations.
- Before release, a fresh copy of `9626247b` succeeded: 553 server tests, 232
  script tests, the browser suite (102) on port 4002 and again on 4123, the CLI
  command check and the identity check; both deliberate breaks (a bad cursor no
  longer refused, the pairing id dropped from the contract) were caught; the copy
  stayed clean. The shared library check succeeded in the real checkout.
  Evidence: `control/coordination/evidence/regents-sh-9626247b-*`.
- Live checks: the image is labelled
  `9626247b05fde174f559b15c1f5ed46ad0dea114`; /healthz answers ok; the published
  contract lists the pairing id on both agent answers; an unsigned history read
  is still refused before any cursor is looked at; /, /stake, /account, /redeem,
  /paper-pro-daily, /articles and /literature answer 200 at 390 and 1280 in
  headless Chromium with no page errors and no sideways scroll.

## 2026-10-19 — Agent words match the template

- The Connect your agent page and its Markdown guide now say what the template
  says an agent cannot do: it can never use your wallet, change your account or
  pair other agents. The old line said an agent can't sign anything, which was
  wrong: it signs its own requests.
- Account's "What your agents may spend" section only invites a person to turn
  spending on while spending can be turned on. Until then it shows only "Agent
  spending opens soon."
- One check covers this: with spending closed the section shows only the
  "opens soon" line, and with it open it shows only the invitation.

## 2026-10-19 — Safety headers on files, deploy names its commit, quiet tests

- Images, icons and other files served as they are now carry the same "this
  page may do nothing" safety headers as the template's, and a check proves it.
- A deploy refuses a commit that is not on GitHub main, and the image now
  carries the commit it was built from.
- Test runs print nothing from tests that succeed; a failing test still shows
  everything it logged.

## 2026-10-19 — Home page share picture shows $REGENT and a larger crown

- The picture shown when the home page is shared now has a large $REGENT line
  under "The community-owned agentic product lab." and a larger crown alone
  in the top left.
- The six site tiles stay inside the picture's frame; patchbay.help and
  autolaunch.sh were cut off at the right edge.
- The picture's description names $REGENT and the crown.
- Picture and description only: no page, Stake or Redeem change, no migrations.

## 2026-10-19 — Pair New Agent shows where to choose your agent

- Pressing Pair New Agent on the Account page now briefly flashes the agent
  pictures in the side panel, so you can see where to choose. If the panel is
  scrolled away from them, it brings them into view. On a phone the button
  opens the panel and the pictures flash there. With reduced motion turned on,
  the pictures are outlined for a moment instead of flashing.

## 2026-10-19 — Regents v209 released

- v209 (`4e10f083`) went live as Fly v209 at about 00:10Z on 20 Oct, on Sean's
  1. a (the flash) and the standing permission for ordinary releases. It carries
  the agent words that match the template, safety headers on files served as
  they are, the deploy that names its commit, the home share picture with
  $REGENT, and the Pair New Agent flash. The rollback is v208 (`9626247b`). No
  migrations.
- Before release, the full check succeeded in the checkout: 555 server tests,
  232 script tests and 105 browser tests, with no warnings printed. The one
  Docker-backed packaging test did not run: Docker on the Mac was not answering.
- Live checks: the image is labelled
  `4e10f0830456cc9f8f163a3d12fec63f005d2d58`; one machine runs; /healthz answers
  ok; the live share picture matches the repository's; a share image carries all
  four safety headers; /, /start and /account answer 200 at 390 and 1280 in
  headless Chromium with no page errors and no sideways scroll; the log tail
  shows only the old machine's handover message.

## 2026-10-20 — Three checks that sometimes failed now fail only for real faults

- The design showcase check waits for the palette controls after reloading the
  page, as it already does on first load. A press made before they were ready
  was lost, so the check once read the wrong palette's colour.
- The page walk no longer counts Chrome's note that the /redeem intro video was
  stopped because the walk left the page before it played. Visitors see nothing.
- The sign-in failure log check reports from an address no other check uses.
  The log keeps at most 20 lines a minute for each address, so when other
  checks from the same address ran first, its line was never written.
- Checks only: nothing on the site changes.

## 2026-10-20 — One request limit for the API, and a size limit on requests

- `/healthz` and every `/api` address now share one budget of 120 requests a
  minute for each client address, as on the template site. Pairing is still held
  to 10 a minute on top of it. Before, only agent pairing and check-ins had a
  limit (check-ins 60 a minute) and the public reads had none.
- Past a limit the answer is 429 with the code `too_many_requests`, the message
  `Too Many Requests` and `Retry-After`, the same words the template uses. It
  was `rate_limited`. Every answer lists the budgets it counted against in the
  `RateLimit` and `RateLimit-Policy` headers.
- Requests with a body over a megabyte are refused before the body is read
  (the largest request the site takes is a few kilobytes). File-upload bodies,
  which nothing on the site uses, are no longer read.
- The API description (`/openapi.json` and the YAML contract) is now version
  3.0.0 and lists the headers and the 429 on every operation; /docs, /llms.txt
  and /agents.md say the same.

## 2026-10-20 — Regents v210 released

- v210 (`70796965`) went live as Fly v210 at about 03:57Z on 20 Oct, on the
  standing permission for ordinary releases. It carries the one request limit
  for the API and the size limit on requests, and the three steadier checks
  (`b5910f90`). The rollback is v209 (`4e10f083`). No migrations.
- Before release, the full check succeeded on this commit: 557 server tests,
  232 script tests and 105 browser tests.
- Live checks: the machine runs the image labelled `main-707969659c15`; one
  machine runs; /healthz and /api/v1/products answer 200 with
  `RateLimit-Policy: "default";q=120;w=60`; /openapi.json is version 3.0.0;
  /docs and /llms.txt state the new limits; /, /stake and /account answer 200
  at 390 and 1280 in headless Chromium with no page errors and no sideways
  scroll; the log tail shows ordinary requests only.

## 2026-10-20 — Health check in JSON for agents

- `GET /api/v1/health` answers `{"status": "ok"}` when the site and its
  database answer, and 503 with the code `unavailable` when the database does
  not, as on the template site. It stays open while the product pages are
  closed, like `/healthz`, and uses the same request budget.
- The API description now says that `/healthz` also checks the database and
  answers 503 `unavailable` when it does not; it said only that the web service
  was responding. `/openapi.json` is version 3.1.0; /docs and /llms.txt list the
  new address.

## 2026-10-20 — Regents v211 released

- v211 (`495d9da7`) went live as Fly v211 at about 04:13Z on 20 Oct, on the
  standing permission for ordinary releases. It carries the health check in
  JSON at `/api/v1/health`. The rollback is v210 (`70796965`). No migrations.
- Before release, the full check succeeded on this commit: 558 server tests,
  232 script tests, 105 browser tests and the Docker packaging test.
- Live checks: the machine runs the image labelled `main-495d9da70494`; one
  machine runs; `/api/v1/health` answers 200 `{"status":"ok"}` with
  `Cache-Control: no-store` and the request-limit headers; /healthz answers ok;
  /openapi.json is version 3.1.0 and lists the new address; /, /stake and
  /account answer 200 at 390 and 1280 in headless Chromium with no page errors
  and no sideways scroll; the log tail shows only the old machine's handover.

## 2026-10-20 — Stake page buttons keep one line on a phone

- On phones up to 360 wide, the Unstake tab of the Stake box broke across three
  lines ("UNST / AKE") and stood taller than Stake, and at 320 wide the
  Connect wallet button broke over two lines. On phones these labels now keep
  one line with slightly tighter spacing, so the switch is one even row and the
  button keeps its height from 320 wide up. Wider screens are unchanged.
- Not yet released. No database migrations. Nothing about how staking works
  changes.

## 2026-10-20 — Sign-in pages allow the template's picture sources

- Pages that can sign someone in allowed a picture from any https address. They
  now allow the template's list: this site, ENS pictures (on every page, as on
  the template), Privy's own pictures and WalletConnect's wallet logos, plus
  this site's picture store at `media.regents.sh` for the Regents Club Pass
  artwork. A Regent profile picture hosted elsewhere no longer shows.
- Sean's 2. a, 20 Oct 13:23Z. Not yet released. No database migrations.

## 2026-10-20 — HTTPS notice on the health check, as in the template

- `/healthz` was the one public address answered without the
  Strict-Transport-Security notice, because the site exempted the path so
  Fly's plain-HTTP health check would not be redirected. As in the template,
  the site now exempts the machine's own names (`localhost`, `127.0.0.1`)
  instead, and Fly's check in `fly.toml` and `fly.staging.toml` sends
  `Host: localhost`. Public visits to `/healthz` now carry the notice.
- Sean's 3. a, 20 Oct 13:23Z. Not yet released. No database migrations.

## 2026-10-20 — Regents v212 released

- v212 (`3d29a488`) went live as Fly v212 at about 13:37Z on 20 Oct, on Sean's
  1. a, 2. a and 3. a (13:23Z). It carries the Stake page phone fix
  (`96813c28`), the template's picture sources on sign-in pages (`1ba27398`)
  and the HTTPS notice on `/healthz` (`3d29a488`). The rollback is v211
  (`495d9da7`). No migrations.
- Before release, the full check succeeded on this commit: 558 server tests,
  232 script tests, 105 browser tests, the Docker packaging test and the
  command-line check.
- Live checks: one machine runs the image labelled `main-3d29a488839f`; Fly's
  health check, which now sends `Host: localhost`, is passing; `/healthz` and
  `/` over HTTPS carry `Strict-Transport-Security: max-age=31536000`; plain
  HTTP to `/healthz` is redirected to HTTPS; sign-in pages list `img-src 'self'
  data: https://metadata.ens.domains blob: https://explorer-api.walletconnect.com
  https://media.regents.sh` and reading pages `img-src 'self' data:
  https://metadata.ens.domains`; /, /stake, /redeem/gallery, /account and
  /docs answer 200 at 320, 390 and 1280 in headless Chromium with no page
  errors, no blocked pictures and no sideways scroll; the Club Pass artwork
  draws on /redeem/gallery; Connect wallet on /stake keeps desktop height at
  320 and 360.

## 2026-10-20 — Stake, Redeem and Paper Pro Daily share pictures match the home picture

- The pictures shown when /stake, /redeem and /paper-pro-daily are shared now
  use the home picture's dark look: the dark panel with its corner marks, the
  crown alone in the top left and a cream pixel headline.
- Each keeps its own words and picture: the Stake steps, the Animata artwork
  and the three paper first pages.
- The page's address sits beside the crown, inside the part of the picture X
  keeps on a narrow screen and away from the corner where X writes the site's
  name.
- Pictures only: no page, Stake or Redeem change, no migrations.

## 2026-10-20 — Regents v213 released

- v213 (`54f76759`) went live as Fly v213 at about 13:48Z on 20 Oct. It carries
  the dark share pictures for /stake, /redeem and /paper-pro-daily, released for
  the Design and Animation chief on Sean's 1. a (13:34Z). The rollback is v212
  (`3d29a488`). No migrations.
- Before release, the full check succeeded on this commit: 558 server tests,
  232 script tests, 105 browser tests, the Docker packaging test and the
  command-line check.
- Live checks: one machine runs the image labelled `main-54f767598935`; Fly's
  health check is passing; /stake, /redeem and /paper-pro-daily name
  `stake-d63b80c2…`, `redeem-fdec377e…` and `paper-pro-daily-3a7579fa…`, and
  each answers 200 `image/png` at the new picture's size.

## 2026-10-21 — Outbound connections trust castore's certificate list

- What: the site now trusts the certificate list castore 1.0.22 ships
  (Mozilla's), instead of the server image's Debian list, for every outbound
  connection: `Regents.Application` loads it first thing, and the Fly database
  connection names the same file (`Regents.DatabaseConfig`, which runs before
  the application starts). `platform/Dockerfile` no longer copies Debian's list
  into the image. Copied from ash-template `fd9776a0`.
- Checked: `platform/test/regents/trusted_roots_test.exs` (the trusted list is
  castore's, without the three dropped eMudhra roots; it fails when the load
  line is taken out). The database tests now expect castore's file. The full
  check, including the required-fixes check against ash-template's main.
- Why: eMudhra's intermediate certificates were compromised (20 Oct 2026).
  castore dropped their roots the same day; Debian bookworm's list still has
  them. Released on Sean's 40a (21 Oct 08:12Z) for this one release.

## 2026-10-21 — Regents v214 released

- v214 (`acad2922`) went live as Fly v214 at about 09:12Z on 21 Oct. It carries
  castore's certificate list for every outbound connection, released on Sean's
  40a (08:12Z). The rollback is v213 (`54f76759`). No migrations.
- Before release, the full check succeeded on this commit: 559 server tests,
  232 script tests, 105 browser tests, the required-fixes check against
  ash-template main `45aebaa3`, the command-line check and the identity check.
- Live checks, from the machine itself: the eMudhra test site
  dv-g3b-emudhra.we-have-a-problem.com is refused as an unknown issuer, while
  Privy, Base, OpenRouter, GitHub and siwa.regents.sh connect; 118 trusted
  roots; castore 1.0.22; the image has no Node, Python, curl or OpenSSL program
  and no /etc/ssl/certs, so nothing else in it keeps its own certificate list.
  One machine runs `main-acad29221bdd` with its health check passing.

## 2026-10-21 — Info tips open on hover; vgpu's agent tools server uses the fixed MCP library

- What: the shared UI library moves to design-system `5b4f47ec` (from
  `f9b0e255`), the pin ash-template has, and `platform/assets/js/app.ts` loads
  its `tip.mjs`, so every "i" tip opens while a mouse rests on it and closes a
  moment after it leaves; a click keeps it open, and touch and keyboard still
  use a press. The new pin also brings the library's charcoal window backdrop,
  account card and address changes, and its cards no longer tilt: only the
  light on the foil follows the pointer. `assets/js/hooks/holographic_card.ts`
  is now the template's, and the overview's product cards and the home page's
  product tabs drop their tilt settings. The library's buttons are about 40px
  tall under a mouse and 44px under a finger, so the Stake browser test no
  longer asks for 44px at desktop width; its touch-phone test keeps that check. `platform/package.json` overrides
  `@modelcontextprotocol/server` and `@modelcontextprotocol/core` to 2.3.1 with
  zod 4.6.7, and zod 4.6.7 under vgpu 0.6.0, as ash-template `1d2c2ffe` does.
  Only `npx vgpu mcp`, the docs and examples server the vgpu-island skill
  points agents to, uses that library; the site's pages do not.
- Checked: `npm ls` shows server and core at 2.3.1 under vgpu; `npm audit`
  finds nothing; `vgpu mcp` starts over stdio and lists its docs and examples
  tools. The full check.
- Why: Sean's 1. a (20 Oct 23:23Z) and go (21 Oct 00:58Z) for hover tips on
  every site. MCP server 2.0.0 carries GHSA-rvq5-wwqv-78pq, GHSA-46jr-4wx8-v453
  and GHSA-jm63-cq47-j5jp, fixed in 2.3.0; its licence moved from MIT to
  Apache-2.0.

## 2026-10-21 — Regents v215 released

- v215 (`25600003`) went live as Fly v215 at about 09:28Z on 21 Oct. It carries
  the hover info tips (Sean's go, 21 Oct 00:58Z), the shared UI library at
  design-system `5b4f47ec` and the MCP library at 2.3.1. The rollback is v214
  (`acad2922`). No migrations.
- Before release, the full check succeeded on this commit: 559 server tests,
  232 script tests, 105 browser tests, the required-fixes check, the
  command-line check and the identity check.
- Live checks: one machine runs `main-25600003927e` with its health check
  passing. On the live /stake page in headless Chromium, a tip in the library's
  markup opens while the mouse rests on its "i", closes after the mouse leaves,
  and stays open after a click; the page raises no errors.

## 2026-10-21 — The home page is the fleet figure and REGENT staking

- `/` now opens with "Agents build together. Useful work creates value." and,
  under it, a web of five cards: Keyfleet, Techtree, Patchbay, Autolaunch and
  Stake $REGENT, each a name and a slogan that opens its app. Labelled lines
  join them: Ideas, Blockers and Projects go out from the fleet, and USDC goes
  to staking from Keyfleet, Patchbay and Autolaunch. A label's tip gives the
  full share behind it. The lines flow, drawn with vgpu; a card under the
  pointer or keyboard lights its lines. Without WebGPU, or with less motion
  asked for, the still lines show. The figure fits in the top half of the first
  screen on a computer, and stacks the apps around the fleet on a phone.
- REGENT staking sits beside the figure on the same page. Its "Where staking
  USDC comes from" panel states exactly what reaches staking (every Credits
  purchase on Base, 10% of each new Key sale, 10% of each paid Patchbay
  priority report and each 0.10 USDC assist, 2% of each Revstake token's USDC
  revenue and 1% of each Memestock trade on Base) and how each deposit is
  split by the share of REGENT staked.
- The cube home page moves to `/vgpu-demo`, unchanged apart from its links,
  which now lead to `/`, and its staking card, which states the same split as
  the home page. It stays dark and stays open while the rest of the app is
  closed. `/stake` answers 301 to `/` for good; its share picture is removed.
- The Overview page (`/app`) is removed with no redirect: its page, styles,
  drawings, side-panel link, page title and checks are gone, and so is the
  signed-in wallet read only it used (`Regents.Staking.account`). Pages that
  named `/app` as their parent now name `/`, and checks that opened `/app` as
  an ordinary signed-in page now open `/autolaunch`, and the Showcase links to
  `/` in their place.
- Agents read the same figure, with every example step, its tools and its
  approvals, as `GET /api/v1/example-workflows`, the
  `regents_example_workflows` browser tool and the home page's Markdown, all
  from `RegentsWeb.ExampleWorkflows`. The page itself shows only the slogans.
- New checks: `test/browser/fleet_figure.spec.ts` (no card or label covers
  another at 1440, 1024, 390 and 320, nothing leaves the figure, it fits in
  the top half of a 1440 by 900 screen, the cards' links, and the still lines
  without a GPU frame) and `test/regents_web/example_workflows_test.exs` (the
  agent read, the Markdown, the revenue split, the /stake move).
- The cube's checks move with it: `test/browser/vgpu_demo.spec.ts` and
  `test/regents_web/vgpu_demo_live_test.exs`.

## 2026-10-22 — The web-of-cards home page is parked, not released

- What: `cd12bc0c` reverts `f22ed359` (the entry above, "Home page: a web of
  cards…"). The cube stays the home page, `/stake` stays the staking page and
  `/app` stays. The tree matched live v215 (`25600003`) again. That revert also
  dropped the entry above from this file; it is restored here, since this file
  is append-only.
- Why: Sean, 21 Oct 11:18Z: "these cards are not what I want. hold for later.
  dont release". The design stays in `f22ed359`; reverting `cd12bc0c` brings it
  back when Sean returns to it.

## 2026-10-22 — Measurements under the template's names, in microseconds

- What: the site measures the way ash-template does, through Peep, in whole
  microseconds. Database waits are `health.db_queue.microseconds` (Fly Sentinel's
  tiles read this name), each query's whole time
  `regents.repo.query.microseconds`, each request's time by its route pattern
  `regents.request.duration.microseconds`, background jobs by outcome and time,
  and the engine's memory and run queues. Staking chain reads are the counter
  `regents_staking_rpc_requests_total`. The old seconds-based names are gone (hard
  cutover); Sentinel's database-wait tiles show "Waiting for data" until they read
  the microsecond name. `/agents.md`, `/skill.md` and `/llms.txt` now carry an ETag
  and cache tags so shared caches may keep them; req and telemetry_poller move to
  version ranges as in the template.
- Checked: 563 server tests, 232 script tests, 105 browser tests (headless
  Chromium; WebKit not run on the Mac), the required-fixes check against
  ash-template `36e32b8c`, the command-line check and the identity check (16 tests).
- Why: Sean approved the quick wins on 21 Oct (10:33Z and 11:02Z), including
  every site following the template's microsecond metric names.

## 2026-10-22 — Regents v216 released

- v216 (`cd8fe2ad`) went live as Fly v216 at about 22:06Z on 22 Oct. It carries
  the measurements under the template's microsecond names and the cached agent
  documents. The rollback is v215 (`25600003`). No migrations, no library pin
  change.
- Before release, the full check succeeded on this commit (see the entry above).
- Live checks: one machine runs `main-cd8fe2adc56b` with its health check
  passing; `/`, `/stake`, `/redeem`, `/account`, `/docs` and `/app` answer 200 and
  `/vgpu-demo` answers 404 (the parked page is not live); `/agents.md`,
  `/skill.md` and `/llms.txt` carry their ETag and a five-minute public cache. A
  repeat read with that ETag still gets the whole document (200, not 304), as on
  template.regents.sh. The new metric names were not read on the live machine.

## 2026-10-22 — New lines in a list only fade in, as in ash-template

- What: a line joining a list (Account and Redeem) fades in where it lands instead
  of sliding in; the lines already there still glide to make room. The list motion is
  now word for word the template's.
- Why: a slide or a grow left a leftover mark written on the new line once it
  settled; the template fixed this on 19 Oct (kit note 6) and regents.sh had not
  taken it.

## 2026-10-22 — Every site applies shared changes the same way

- `/app/bin/migrate-shared` now uses ash-template's code: one list of the shared
  Identity, Agents, Credits, Points and Payments libraries, filtered to the ones
  this release carries. Regents is no longer the only site that applies shared
  changes; every site carries this same command (Sean, 19 Oct 2026: every site
  works the same). A deployment still never applies them.
- The release check and `/app/bin/pending-migrations` read the same list, so a
  deployment now also stops while a shared Identity or Payments change is
  missing. The staging bootstrap applies every shared change before Regents' own
  migrations, as production does.

## 2026-10-22 — Release commands and local databases set up like the template

- `mix regents.setup_local_auth`, which `mix test` runs, now prepares a local
  database exactly as `bin/bootstrap-staging` prepares staging, through one
  shared step: the tables Regents reads but does not own, every shared change
  this release carries, then Regents' own migrations. Before, local setup ran
  Agents, then Regents' migrations, then Credits and Points, and skipped
  Identity and Payments.
- The release commands now have ash-template's shape: `bootstrap_staging`,
  `pending_migrations` and `migrate_shared` take the test options directly
  instead of through separate test-only versions, and a shared library whose
  ledger does not exist yet counts as wholly unapplied. Regents' own copy of
  Identity is unchanged.
- New release tests cover the listing of a missing shared change, the
  deployment check that refuses it, and `migrate-shared` applying every shared
  change once.

## 2026-10-22 — Regents v217 released

- v217 (`449cd52f`) went live as Fly v217 at about 22:18Z on 22 Oct. It carries
  the shared-changes command and release check in the template's shape (Sean,
  20 Oct, "1. a 2. a") and the list fade-in. The rollback is v216 (`cd8fe2ad`).
- The release step (`/app/bin/migrate`) succeeded, so every shared change this
  release carries (Identity, Agents, Credits, Points, Payments) was already in
  production's ledgers; `migrate-shared` was not run and was not needed.
- Before release, on this commit: 565 server tests, 232 script tests, 105
  browser tests.
- Live checks: one machine runs `main-449cd52f669c` with its health check
  passing; `/`, `/stake`, `/redeem`, `/account`, `/docs` and `/app` load in
  headless Chromium at 1280 and 390 wide with no errors and no sideways scroll.
  WebKit not run on the Mac.

## 2026-10-22 — Elixir 1.20.4 on OTP 29, as in ash-template

- `.tool-versions`, the Dockerfile (each image digest under its tag) and both
  `mix.exs` files move to Elixir 1.20.4 on Erlang/OTP 29.1.2 and Node 26.12.0,
  the template's toolchain (ash-template `ba35e7a`).
- elixir-utils moves to `3ffd1647` (same toolchain). It brings one shared
  change, an index on Credits holds by owner and time held; the Privy wallet
  changes after it are not taken.
- Newer libraries: Ash 3.37, AshOban 0.10.2, AshSql 0.8.3, Spark 2.7.8,
  LiveView 1.2.13, Nebulex 3.1, esbuild 0.10.1 and others; ash_postgres stays at
  2.13.0.
- Phoenix stays at 1.8.15. On 1.8.16 the server ends a signed-out page's live
  connection as a normal close, which LiveView answers with a reload 5 to 10
  seconds later, so a page stayed looking signed in for that long after sign
  out, after another tab signed out, and after a refused sign-in (four browser
  checks caught it). 1.8.15 ends it as "going away", so the page reconnects, is
  refused and reloads signed out at once. Moving the page's own reload ahead of
  the server's close goes to ash-template first.
- The pairing message comes from the library's three-argument text, as in the
  template; two tests that pinned the old wording now check the behaviour
  (the refusal's code, and that the message carries the code and the guide).
- Checked on this toolchain: 565 server tests, 232 script tests, 105 browser
  tests, required fixes (ash-template `cde83109`), CLI commands, identity 16.

## 2026-10-22 — Regents v218 released

- v218 (`1c144216`) went live as Fly v218 at about 22:40Z on 22 Oct: Elixir
  1.20.4 on OTP 29, Node 26.12, elixir-utils `3ffd1647`, Phoenix held at
  1.8.15. The rollback is v217 (`449cd52f`).
- The release step (`/app/bin/migrate`) succeeded, so the Credits holds index
  was already in production; `migrate-shared` was not run.
- Live checks: one machine runs `main-1c1442165212` with its health check
  passing; `/`, `/stake`, `/redeem`, `/account`, `/docs` and `/app` load in
  headless Chromium at 1280 and 390 wide with no errors and no sideways scroll;
  no errors in the machine's recent log. WebKit not run on the Mac.

## 2026-10-22 — Each agent on the Account page names its wallet

- design-system moves to `5dd12626`, as in ash-template (`a993f2d`). Each agent
  row on the Account page shows the agent's own wallet beside its name: the
  short form opens the full address, its icon copies it, and its arrow opens it
  on Basescan. The contact line says "Last check-in".
- The agent's window shows its address the same way instead of as plain text,
  and says "Last check-in", in the library's words.
- Rows carry `light: nil` and `light_label: nil`, as the library now asks of a
  site without check-in lights.
- Checked: the Account agents test now proves each of two agents' rows names its
  own wallet.

## 2026-10-22 — The side panel opens under the header

- Below a wide screen the side panel opened 1 px too high and covered the
  header's bottom line; on a phone the menu and its backdrop did the same. The
  shell now names the header's height once and opens all three where the
  header's line ends, below the frame's top rule (ash-template `b9d301f`,
  design-system `STYLE.md` "The side panel opens under the header").
- New browser check `platform/test/browser/layout.spec.ts`: the panel at 2000,
  1280, 800 and 390 wide, and the phone menu at 390.
- Checked: 565 server tests, 232 script tests, 107 browser tests, required
  fixes.

## 2026-10-22 — Regents v219 released

- v219 (`70ed94f6`) went live as Fly v219 at about 22:53Z on 22 Oct: each agent
  on the Account page names its wallet (design-system `5dd12626`), and the side
  panel, phone menu and its backdrop open under the header's line. The rollback
  is v218 (`1c144216`).
- The release step succeeded; no shared change was waiting.
- Live checks: one machine runs `main-70ed94f6c1da` with its health check
  passing; `/`, `/stake`, `/redeem`, `/account`, `/docs` and `/app` load in
  headless Chromium at 1280 and 390 wide with no errors and no sideways scroll;
  on regents.sh the phone menu's top meets the header's line at 390 (57 px) and
  800 (65 px) wide. WebKit not run on the Mac.

## 2026-10-23 — The command check follows regents-cli 1.10.16

- `make check-cli` now runs regents-cli's checker at `2c98218e` (1.10.16, live
  on PyPI), which carries regents.sh's reading commands: protocol articles,
  literature, profiles and research. Asked for by the regents-cli chief.
- Checked: `make check-cli` (cli/commands.json ok). No site code changed.

## 2026-10-23 — Security update: plug_crypto 2.2.1

- `platform/mix.lock` and `identity/mix.lock` move plug_crypto from 2.2.0 to
  2.2.1 (advisory GHSA-ffw9-w85g-f2vh, medium: the secret key base could show in
  stack trace arguments). `mix hex.audit` is clean in both apps again. Lock-only;
  no site code changed. Reported by the Autolaunch chiefs to every site.

## 2026-10-23 — Regents v220 released

- v220 (`135bcd5c`) went live as Fly v220 at about 15:48Z on 23 Oct: plug_crypto
  2.2.1 in both locks (GHSA-ffw9-w85g-f2vh), plus the regents-cli 1.10.16 check
  pin. The rollback is v219 (`70ed94f6`).
- Checked before release: server tests 565, JavaScript 232, browser walk 107/107,
  identity 16, required fixes and the command check all succeeded; `mix hex.audit`
  clean in both apps.
- Live checks: one machine runs `main-135bcd5cb89f` with its health check
  passing; `/`, `/stake`, `/redeem`, `/account` and `/docs` load in headless
  Chromium at 1280 and 390 wide with no errors and no sideways scroll. WebKit not
  run on the Mac.

## 2026-10-23 — Two wallets at sign-in, and sign-out lets go of every wallet

Sean, 22 Oct 2026, "1. a": build now; 23 Oct 2026, "1. a": release. Copied from
ash-template 8e07e8c, 7896c0c, ec39cb2, 70e4a82, cde8310 and f79a3149.

- Privy makes a Regents wallet for everyone at their next sign-in. The Account
  page names it as "Regents embedded wallet" and, only when the person signed in
  with a wallet of their own, that wallet as "User wallet". Every wallet on the
  page uses the shared address component. The sign-in cookie keeps which wallet
  is which; it grants nothing.
- The person's own wallet stays their main wallet (elixir-utils `dcd60691`).
- A page whose browser still holds a Privy sign-in with a wallet signs back in
  when it loads, unless the person pressed Disconnect. Closing the sign-in window
  says nothing. The sign-in failure words match the template.
- Sign-out lets go of every connected wallet before Privy signs out and never
  waits on one. On a signed-out page, Connect wallet first ends any Privy
  sign-in the browser still remembers, so it can never sign the last person
  back in (template f79a3149).
- Phoenix 1.8.16. A sign-out from another tab, or a refused sign-in, now reloads
  the page within LiveView's 5 to 10 seconds, as on the template; a page's own
  sign-out still reloads at once.
- Left out: the template's display-name save from the browser, which comes with
  the Account page port.

## 2026-10-23 — Regents v221 released

- v221 (`462c3935`) went live as Fly v221 at about 18:28Z on 23 Oct, on Sean's
  "1. a": two wallets at sign-in, sign-out lets go of every wallet, and the
  template's Connect wallet fix (f79a3149). The rollback is v220 (`135bcd5c`).
- Checked before release: server tests 569, JavaScript 242, browser walk 107/107,
  identity 16, required fixes (template f79a3149) and the command check all
  succeeded; `mix hex.audit` and sobelow clean.
- Live checks: the machine runs `main-462c39355135` with its health check
  passing and no errors in its logs; `/`, `/stake`, `/redeem`, `/account`,
  `/docs` and `/app` load in headless Chromium at 1280 and 390 wide with no
  errors and no sideways scroll. A real Privy sign-in was not walked headless.
  WebKit not run on the Mac.

## 2026-10-23 — The command check follows regents-cli 1.10.17

- `make check-cli` now runs regents-cli's checker at `773f8a67` (1.10.17, live
  on PyPI). A paired command's help now names only that site's own pairing; no
  regents.sh command or contract changed. Asked for by the regents-cli chief.
- Checked: `make check-cli` (cli/commands.json ok). No site code changed.
## 2026-10-23 — Staking reads Base every five minutes

- The shared staking reading (contract totals, revenue, supply) is now read from
  Base every five minutes instead of every minute, to cut paid node calls. It is
  read again within ten seconds after a signed-in person's on-chain press is
  confirmed, or after they press the new read-again icon beside "Updated …" on
  Stake (the shared `Regent.Primitives.last_read`, design-system `af32c1d3`).
  Many presses close together cost one read: the refresh job is unique and waits
  for the ten-second gap.
- `Regents.ChainRefresh` (copied from ash-template's `AshTemplate.ChainRefresh`)
  asks every chain reader the site names to read again; the staking cache is its
  one reader. The old "refreshed for everyone moments ago" refusal is gone: a
  press soon after a reading now waits for the gap instead of being turned down.
- The "Refresh Data" button at the foot of Stake's actions is replaced by the
  icon. Redeem's own "Refresh Data" is unchanged.

## 2026-10-23 — Credits deposits read every five minutes

- elixir-utils `e600ed34` (was `dcd60691`): the shared Credits deposit reader runs
  every five minutes instead of every minute; a person's own Buy is still credited
  within a minute. The pin also brings the library's side panel offering IronClaw
  in NemoClaw's place and the Hermes pairing line that keeps the key paired with.
- design-system `30d16360` (was `af32c1d3`): the read-again icon as it landed on
  design-system main, with its tip-figure and plug_crypto 2.2.1 changes.

## 2026-10-23 — Regents v222 released

- v222 (`21aa6efb`) went live as Fly v222 at about 19:20Z on 23 Oct, handed over
  by the RPC usage thread (Sean "1 a" there): staking figures read from Base every
  five minutes and again after a confirmed press or the read-again icon, and pins
  to design-system `30d16360` and elixir-utils `e600ed34` (Credits deposits read
  every five minutes, IronClaw in the side panel, the Hermes pairing line). The
  rollback is v221 (`462c3935`).
- Checked before release: server tests 569, JavaScript 242, browser walk 108/108,
  identity 16, required fixes (template `b59c6766`) and the command check all
  succeeded. No database migrations.
- Live checks: the machine runs `main-21aa6efba13e` with its health check passing
  and no errors in its logs; `/`, `/stake`, `/redeem`, `/account`, `/docs` and
  `/app` load in headless Chromium at 1280 and 390 wide with no errors and no
  sideways scroll. The read-again icon shows only signed in, so it was not seen
  live. WebKit not run on the Mac.

## 2026-10-23 — The Pair New Agent box never crashes with nothing chosen

- `RegentsWeb.PairingBox` is now the template's (ash-template `13379ab`). A page
  reconnecting sends the pairing form back with no agent picked, and a submit can
  come before a choice; both crashed the side panel before (Sentinel, from
  Patchbay's error mail). The box now stays as it is.
- Also from the template: each agent keeps its own code until it expires, so
  choosing another agent and coming back shows the same message, and Make a new
  code replaces only the chosen agent's. A code that couldn't be made is logged
  by the kind of failure only.
- Checks: two new walks in `platform/test/browser/pair_new_agent.spec.ts`; both
  fail on the old box (the crash walk with `channel_crash`) and succeed on the new.

## 2026-10-23 — A staking read asked for during a running pass still happens

- `Regents.Staking.SnapshotRefresh` is unique only while it waits
  (`states: [:available, :scheduled]`), as the template's chain-events skill says.
  Before, a pass already running counted too, so an ask that came while it read
  (a press that landed after its read) was dropped until the next five-minute turn.
  Asked for by the ash-template chief.
- Checks: `stake_live_test.exs` "REFRESH_WHILE_A_PASS_RUNS" fails on the old
  setting and succeeds on the new.

## 2026-10-23 — The Keyfleet page's second button says "See Keyfleet #1 Public Pages"

- On `/keyfleet` the second button now reads "See Keyfleet #1 Public Pages" (was
  "See the Regents Club fleet"), Sean's words. It still opens
  keyfleet.ai/app/fleets/regents_club.

## 2026-10-23 — v223 and v224 release records

- v223 runs `93d25062` (the template's Pair New Agent box and the staking read
  during a running pass); the rollback is v222 (`21aa6efb`). Sentinel's
  after-read: healthy, no errors or crashes since release. Its one note, that
  links to Paper Pro Daily cross into another live session and reload the page,
  is fixed by the entry below.
- v224 runs `c3691f4c` (the Keyfleet button's words); the rollback is v223
  (`93d25062`). Health check passing.

## 2026-10-23 — Paper Pro Daily and AI & SCIFI carry the whole side panel

- `/paper-pro-daily` and `/literature` were their own LiveViews drawing the shell
  without its agents, pairing box or Credits button, so signed in their side panel
  showed only Sign out and Manage Account (Sean). Both are now pages of
  `RegentsWeb.ShellLive` in the product shell, the way the template runs every
  page with the side panel, so they show the whole panel and moving between them
  and the rest of the app no longer reloads the page.
- Paper Pro Daily's feed is `RegentsWeb.ShellLive.PaperProDaily`: read when the
  page opens and at each UTC midnight while it stays open, with one timer at a
  time, let go when the page is left. `RegentsWeb.LiteratureLive` is gone.
- Both stay open to everyone while the launch gate is closed, events included
  (`RegentsWeb.Live.LaunchGateHook`).
- Checks: `platform/test/browser/shell_walk.spec.ts` walks both pages inside one
  visit and, signed in, opens eight shell pages by address and finds the agents,
  the pairing box and the Credits button on each.

## 2026-10-23 — v225 release record

- v225 runs `b4c48cc1` (Paper Pro Daily and AI & SCIFI in the product shell); the
  rollback is v224 (`c3691f4c`). No database migrations.
- Checked before release: server tests 570, JavaScript 242, browser walk 111/111.
- Live checks: the machine runs `main-b4c48cc1099b` with its health check passing
  and no errors in its logs; `/`, `/stake`, `/redeem`, `/account`, `/docs`, `/app`,
  `/paper-pro-daily` and `/literature` load in headless Chromium at 1280 and 390
  wide with no errors and no sideways scroll, and AI & SCIFI moves to Paper Pro
  Daily without a page reload. The side panel shows only signed in, so it was not
  seen live. WebKit not run on the Mac.

## 2026-10-23 — ChatGPT agents' picture, and builds that fetch native code again

- design-system `cbf12f8d` (from `30d16360`): a paired agent of kind "chatgpt"
  draws OpenAI's mark in the side panel and on the Account page; before, that
  picture crashed (ash-template chief). ChatGPT pairing itself stays off.
- GitHub's download redirect now sends headers longer than Erlang's HTTP client
  accepts, so a build without the cached layer stopped at `mix deps.compile`.
  As in ash-template `7745906`: mdex_native takes its native code from its
  maker's mirror (`platform/config/config.exs`), and `platform/Dockerfile`
  fetches ex_keccak 0.7.8's, ex_secp256k1 0.8.0's and vix 0.42.0's files with
  curl into rustler_precompiled's and elixir_make's caches, where each is checked
  against the package's own checksums. vix (pictures) is ours alone; a build
  without the cache found it.

## 2026-10-23 — A page cannot draw half a side panel

- `RegentsWeb.Components.Shell.shell` now requires its Credits panel, pairing
  and agents parts (ash-template `98411ef`), so a page that draws the shell
  without one fails to compile; a caller leaves a part out for someone signed out
  with `:if`. This is the guard against v225's bug, where two pages showed only
  Sign out and Manage Account. The local design showcase's preview, never signed
  in, passes all three that way.
- Checks: dropping the agents part from `RegentsWeb.ShellLive` fails
  `mix compile --warnings-as-errors` with "missing required slot".

## 2026-10-23 — v226 release record

- v226 runs `2c2c79bf` (design-system `cbf12f8d`, the native-code build fix, the
  required side-panel parts); the rollback is v225 (`b4c48cc1`). No database
  migrations.
- Checked before release: server tests 570, JavaScript 242, browser walk 111/111;
  a cache-free Fly build of `acc546a5` succeeded (the first, without vix's file,
  stopped at vix with header_too_long).
- Live checks: the machine runs `2c2c79bf` with its health check passing and no
  errors in its logs; the eight pages load in headless Chromium at 1280 and 390
  wide with no errors and no sideways scroll, AI & SCIFI moves to Paper Pro Daily
  without a reload, and `/images/regent-ui/agents/chatgpt.svg` is served. WebKit
  not run on the Mac.

## 2026-10-23 — Builds on a Mac fetch their own native code

- `platform/Dockerfile` fetches ex_keccak's, ex_secp256k1's and vix's files for
  the building machine's chip (`uname -m`) instead of x86_64 only, so
  `make release` on a Mac (aarch64) no longer asks GitHub for them and stops at
  the long download headers. Fly builds are unchanged (ash-template `8581a96`,
  from Techtree `78c5c5a5`). All six files, and mdex_native's mirror files for
  both chips, answer 200.
- The runtime image installs `libsctp1`, which OTP 29 opens at start. Without
  it every boot and `bin/regents rpc` printed a warning first, which broke the
  release smoke check's database answer on the Mac (Techtree `fadc820d`).

## 2026-10-24 — Elixir 1.20 builds without two warnings

- design-system pinned at `9c2a817` (was `cbf12f8d`): regent_ui asks for Elixir
  `~> 1.19`, so building it on 1.20.4 no longer warns. Nothing else changed.
- `platform/mix.exs` sets `test_ignore_filters` for `test/browser/`, so
  `mix test` no longer warns that the Playwright walk's files match no test
  pattern (ash-template `9204b46`, from Autolaunch).
- Checks: server tests 570, JavaScript 242, browser walk 111/111.

## 2026-10-24 — Machines stop in order

- `platform/fly.toml` sets `kill_signal = "SIGTERM"` and `kill_timeout = "60s"`
  (ash-template `023c8a1`, after Sentinel saw 3 proxy lines at machine stops in
  7 days). Fly's default SIGINT made the VM halt at once, cutting open
  connections and running jobs; SIGTERM lets them drain and finish. The live
  machine had no stop setting. `fly config validate` accepts the file.

## 2026-10-24 — v227 release record

- v227 runs `a4f5e64f` (native files for the building machine's chip,
  `libsctp1` in the runtime image, design-system `9c2a817`, `test_ignore_filters`,
  SIGTERM with a 60 s stop timeout); the rollback is v226 (`2c2c79bf`). No
  database migrations; the release command succeeded.
- Checked before release: server tests 570, JavaScript 242, browser walk 111/111
  on `034ef4cc`; `scripts/release.sh` on the Mac (aarch64) built and smoke-checked
  `b560b280`; a cache-free Fly build of `88bcdcf8` succeeded; `fly config validate`
  accepted `platform/fly.toml`.
- Live checks: the machine runs `a4f5e64f` with its stop setting at SIGTERM and
  1m0s and its health check passing; eight pages load in headless Chromium at 1280
  and 390 wide with no errors and no sideways scroll, AI & SCIFI moves to Paper Pro
  Daily without a reload, and the logs show no errors and no libsctp warning.
  WebKit not run on the Mac.

## 2026-10-24 — Agents install the current command line

- /llms.txt, /agents.md, /docs.md and the start steps now say
  `uv tool install regents-cli==1.10.17` (was 1.10.12), with source commit
  `773f8a67` and the published wheel's SHA256 `2612ac98…`, matching
  ash-template. Sentinel noticed the old pin.
- Checks: every command (15) and option (4) these pages name answers on
  1.10.17; server tests 570, JavaScript 242, browser walk 111/111.

## 2026-10-24 — v228 release record

- v228 runs `8d632fd6` (agent pages install regents-cli 1.10.17); the rollback is
  v227 (`a4f5e64f`). No database migrations.
- Checked before release: server tests 570, JavaScript 242, browser walk 111/111.
- Live checks: the machine runs `8d632fd6` with stop setting SIGTERM / 1m0s and
  its health check passing. The v227 machine was the first stopped by SIGTERM:
  "SIGTERM received - shutting down", one LiveView connection drained, exit code
  0. The new machine's boot shows no libsctp warning. /llms.txt, /agents.md, /docs
  as Markdown and /start name 1.10.17; six pages load in headless Chromium at 1280
  and 390 wide with no errors and no sideways scroll, and AI & SCIFI moves to Paper
  Pro Daily without a reload. WebKit not run on the Mac.

## 2026-10-24 — Builds fetch native code straight from GitHub again

- GitHub trimmed its download redirect's headers (about 5.5 KB against Erlang's
  10,240-byte limit), so `platform/Dockerfile` no longer pre-fetches ex_keccak's,
  ex_secp256k1's and vix's files with curl, and `platform/config/config.exs` no
  longer sends mdex_native to its maker's mirror (ash-template `150c8a7`). Erlang's
  own client fetched all four files from GitHub with certificate checks on.

## 2026-10-27 — The homepage hero opens the app

- The hero's main button is **Enter App**, which opens Stake like the header's App.
  It rests with the marks a main button shows on hover in dark (Powder Blue at
  the two square corners, Tangerine along the two cuts); hover runs the Powder
  Blue on into two full L-edges and keeps the cuts.
- **WebMCP Tools** sits beside it as the secondary button and opens the same tools
  list as before. The shell footer's tools button is unchanged.

## 2026-10-27 — Web server, Ash and signing library security updates

- Bandit 1.14.0 (was 1.13.1; eleven advisories, nine high: HTTP/2, chunked
  bodies, WebSockets, Content-Length), Ash 3.37.2 (was 3.37.0; two advisories)
  and jose 1.11.13 (was 1.11.12; eight advisories), as ash-template `14bdb108` and
  `628d719`. spark, splode, crux and elixir_make moved with them.
- ash_postgres stays at 2.13.0 for now. Its two advisories need attribute
  multitenancy, which no resource here uses; the move to ash-project's fixed copy
  carries a database helper migration and goes out in its own release.
- `scripts/deploy.sh` builds and releases under
  `lockf -k /tmp/regent-shared-db-release.lock`, so releases from this Mac take
  turns on the shared database (ash-template `2012700`).
- Checks: server tests 570, JavaScript 242, browser walk 111/111; `mix hex.audit`
  lists only ash_postgres 2.13.0's two advisories.

## 2026-10-27 — v229 release record

- v229 runs `572230a1` (hero Enter App and WebMCP Tools; Bandit 1.14.0, Ash 3.37.2,
  jose 1.11.13; deploys under the shared-database lock; also carries `7399fea2`,
  native code fetched straight from GitHub). The rollback is v228 (`8d632fd6`).
  No database migrations ("Migrations already up").
- Checked before release: server tests 570, JavaScript 242, browser walk 111/111.
  No other shared-database app had a release in progress.
- Live checks: the machine runs `572230a1` (image label), Bandit 1.14.0 at boot,
  stop setting SIGTERM / 1m0s, health check passing. Eight pages load in headless
  Chromium at 1280 and 390 wide with no errors and no sideways scroll; Enter App
  opens /stake; its marks rest at the square corners and cuts and grow into full
  L-edges on hover; WebMCP Tools opens the tools list. WebKit not run on the Mac.

## 2026-10-27 — One address per page

- An address with a slash at the end, other than the homepage, is now not found:
  the not-found page for a page, the API's not-found answer under /api. Before,
  /contact/ and /about/ (Sentinel, 27 Oct) and others answered with a server error.
  `RegentsWeb.Plugs.NoTrailingSlash`, copied from ash-template `9dd2237` and
  `be54337`, runs right after the error format is chosen.
- Checks: server tests 573 (3 new in `trailing_slash_test.exs`), JavaScript 242,
  browser walk 111/111.

## 2026-10-27 — v230 release record

- v230 runs `c3ab4a63` (one address per page); the rollback is v229 (`572230a1`).
  No database migrations.
- Checked before release: server tests 573, JavaScript 242, browser walk 111/111.
  No other shared-database app had a release in progress; built and released under
  the shared-database lock.
- Live checks: the machine runs `c3ab4a63` with its health check passing; /contact/,
  /about/ and /stake/ answer 404 with the not-found page, /api/v1/products/ answers
  the API's `not_found`, and /, /contact and /api/v1/health answer 200. Eight pages
  load in headless Chromium at 1280 and 390 wide with no errors and no sideways
  scroll, and Enter App opens /stake. WebKit not run on the Mac.

## 2026-10-27 — Ash's database layer from its fixed copy; required values report Ash's error

- ash_postgres comes from ash-project/ash_postgres at `55db7d44` (2.15.2 with #910:
  upserts use the repository's prefix, so rows stay in `regents_app` on the shared
  database), as ash-template `33c5cd1`; ash_sql 0.8.4, ash_phoenix 2.3.26, ash_oban
  0.10.3. Every shared Regent library moves to elixir-utils `e796a9d` (the Credits
  library installs the version 7 helper on a fresh database). `mix hex.audit` is clean.
- Migration `20261027045129_ash_functions_v7_extensions_1` replaces
  `public.ash_required`, the helper every site's queries find, with version 7: the old
  one ran with an empty search path and could not find `ash_raise_error`, so a missing
  required value failed with "function does not exist" rather than Ash's error. It is
  the body ash-template v111 and Patchbay v274 already put there (Sean, 27 Oct "1. a").
- Signed WebMCP calls label themselves `x-regent-client: webmcp/<tool>`, beside the
  proof and never part of it, as elixir-utils now requires.
- Checks: on a database built from every migration, server tests 574 (new
  `test/regents/required_value_test.exs`, which fails with "does not exist" when
  version 6 is put back), JavaScript 242, browser walk 111/111; required fixes against
  ash-template `810223a6` all present; no table written to `public`. Four sign-in tests
  compare account ids rather than whole records, since ash_postgres 2.15.2 adds its
  upsert note to a record's metadata.

## 2026-10-27 — v231 release record

- v231 runs `49745bb1` (ash_postgres from ash-project `55db7d44`, elixir-utils
  `e796a9d`, version 7 `public.ash_required`). The rollback is v230 (`c3ab4a63`) and
  needs no database change: version 7 is the same function under the same name.
- Authority: Sean 27 Oct "1. a" (release with the helper migration).
- Release step: "Migrated 20261027045129 in 0.0s", the one statement
  `CREATE OR REPLACE FUNCTION public.ash_required(…)`. No other shared-database app
  had a release in progress; built and released under the shared-database lock.
- Live checks: the machine runs `49745bb1` with stop setting SIGTERM / 1m0s and its
  health check passing, Bandit 1.14.0 at boot, no error lines. Eight pages load in
  headless Chromium at 1280 and 390 wide with no errors and no sideways scroll;
  Enter App opens /stake, WebMCP Tools opens the tools list, /contact/ answers 404,
  /api/v1/health and /api/v1/products answer 200. WebKit not run on the Mac.

## 2026-10-27 — The agent list reads more clearly

- Account's agent list takes design-system `0c72c964` (Sean 27 Oct, through the
  template chief): each agent's whole name, its address with copy and explorer, and
  its buttons on the line under it; a tip's words read in plain letters beside a
  small-capitals label. The row button is **See Actions** (was "See what it has
  done"), named "See <agent>'s actions" for screen readers, as ash-template `696c76f`.
- The agent window here is still this site's own, so the template's new window
  headings come with the move to the shared `Regent.Account.agent_detail`.
- Checks: server tests 574, JavaScript 242, browser walk 111/111.

## 2026-10-27 — v232 release record

- v232 runs `a1c12207` (agent list from design-system `0c72c964`, See Actions); the
  rollback is v231 (`49745bb1`). No database migrations ("Migrations already up").
- Checked before release: server tests 574, JavaScript 242, browser walk 111/111.
  No other shared-database app had a release in progress; released under the lock.
- Live checks: the machine runs `a1c12207` with its health check passing and no
  error lines; eight public pages load in headless Chromium at 1280 and 390 wide
  with no errors and no sideways scroll, and Enter App opens /stake. The signed-in
  Account list was not opened live (it needs a sign-in); its LiveView tests cover
  See Actions. WebKit not run on the Mac.

## 2026-10-27 — A wallet press certain to fail is never handed to the wallet

- Credits: a Buy pressed before its steps reached the page asks the server for them.
  The reply now leaves out a Buy that the fresh build finds certain to fail (too little
  USDC, or no approval on the chain yet), the same check that disables the button, so
  the button shows why instead of opening the wallet. From ash-template `344a1f4`
  (Keyfleet `1f4049bc`). Redeem and Stake disable no step for a chain reason, so their
  replies are unchanged.
- New property check `platform/test/regents_web/credits_press_test.exs` (fails on the
  old reply), listed in `FEATURES.md`; `stream_data` is now a direct dependency, as in
  the template.

## 2026-10-27 — Small icon buttons keep their own look

- The plain-button defaults (a dark border, a 44 px floor and padding) now sit
  in the lowest style layer, as ash-template has them, so every component's own
  button rule wins over them. The pairing box's copy and new-code icons are small
  and even again instead of sitting in large dark boxes of unequal height.
- Checked in headless Chromium against the live pages at 1280 and 390 px, light
  and dark: every public page draws the same except the pairing icons. WebKit not
  run on the Mac.

## 2026-10-27 — v233 release record

- v233 runs `1d5f997e` (Credits Buy press certain to fail is not handed to the wallet,
  from ash-template `344a1f4`; pairing-box icons keep their own look, button defaults in
  the lowest style layer); the rollback is v232 (`a1c12207`). No database migrations in
  the range; the release step completed.
- Checked before release: server tests 575 (one property check), JavaScript 242,
  browser walk 111/111; required fixes clean against ash-template `344a1f4`. No other
  shared-database app had a release in progress; released under the lock.
- Live checks: the machine runs `1d5f997e` with its health check passing (one failed
  check during the five seconds before the server started listening); the live
  stylesheet carries the layer order; eight public pages load in headless Chromium at
  1280 and 390 wide with no errors and no sideways scroll, and Enter App opens /stake.
  The signed-in Credits panel and pairing box were not opened live (they need a
  sign-in); the property check and browser walk cover them. WebKit not run on the Mac.

## 2026-10-27 — Amounts shown the one Regent way; one listening connection

- Credits amounts follow Sean's one rule (ash-template `d0c846c`): from 1 up, the
  number with exactly 2 decimals; below 1, three significant digits; digits are cut,
  never rounded up. The Credits window's USDC balance, the purchase rows on the Credits
  history and admin pages, and Credits and Points figures from the shared library all
  show it. What an admin locks and sends for a refund stays exact to the millionth,
  since the refund is matched to the purchase to the millionth on chain.
- elixir-utils `e796a9d` -> `78f92d5` (amounts, the listeners' shared connection
  `85d05a7`, siwa_keyring 0.2.0 and the Anthropic error message); mix.lock moves only
  those refs.
- `Regents.SharedChanges` opens one database listening connection,
  `Regents.Notifications` (named `regents-listen`), and starts the Credits, Agents
  and staking listeners on it, so a machine holds one listening connection instead
  of three. New check `platform/test/regents/shared_changes_test.exs`, listed in
  `FEATURES.md`.

## 2026-10-27 — Visit lines: what each visit did, where it came from and where it stopped

- Production now writes one line for each thing a person or agent does on regents.sh
  and how it ended: the page or file asked for, the page shown, each press, each change
  the site saved, each background job, each call to another site and each tool call,
  with how long it took. Every line carries the same few things and nothing else: a
  random id for the browser visit (a cookie that ends when the browser closes, never
  tied to the account), a one-way code for the person or agent that cannot be turned
  back into the account, and whether a page, a page's tool, Regents CLI or another
  program made it. Nothing a person writes, no address and no wallet reaches a line, so
  a visit can be told again from its lines alone. The same as ash-template `e060f3a`,
  `b47b11a`, `7fec82e` and `a254442`.
- A visit's first page names where it came from (an AI answer such as ChatGPT or
  Claude, a search engine, a social site, another site, or nowhere) by name only, never
  the address it came from. A press on any Sign in button and a finished sign-in are
  the journey's first steps. The Privacy Policy's cookies section says so in one
  sentence, the template's own.
- The page reports the few things only it can see: a script error (by page, never its
  message), one of its tools getting no answer, and a wallet press that never reached
  the site. They go together to `/visit-log`, at most 20 at a time, which counts
  against the same per-address budget as the API. The page's tools and the agent tools
  list name the visit when they call the site. Phoenix's own request lines are off in
  production, since the visit lines replace them.
- Not here yet: the "pairing code shown" and "agent paired" steps belong to the
  pairing box, which stays as it is until the shared agents panel arrives from the
  template.
- The home page now has its own live session carrying what the render knew, as in the
  template, so its opening is a line too. New dependency `logger_json` 7.0.4. New
  checks `platform/test/regents_web/visit_log_test.exs`,
  `platform/test/regents_web/visit_log_page_test.exs`,
  `platform/test/browser/visits.spec.ts` and `platform/test/browser/arrivals.spec.ts`,
  listed in `FEATURES.md`.

## 2026-10-27 — Stake share picture: the new words

- The picture a shared /stake link shows now says what staking gives: "Stake
  REGENT to share in Regents Labs' USDC revenue, in proportion to how much of
  all REGENT you stake. The business keeps the rest." Its last tile reads
  "Plus 20% a year in REGENT" (was "Early 20% yield"). Same dark look, frame
  and layout; the words stay clear of the corner where X writes the site's
  name. The picture's description says the same.

## 2026-10-27 — v234 release record

- v234 runs `f6930c94` (Credits amounts shown the one Regent way; one listening database
  connection, `regents-listen`, for Credits, pairing and staking changes); the rollback is
  v233 (`1d5f997e`). No database migrations in the range. The visit lines on main
  (`29ca02b1`) are left out on purpose: the template chief asked every site to hold them
  until Sean answers VISIT-SOURCES-PRIVACY, so the release was built from the commit before
  them.
- Checked before release: server tests 576 (one property check), JavaScript 242, browser
  walk 111/111; required fixes clean. Released under the shared-database lock.
- Live checks: one machine runs `f6930c94` (image label `main-f6930c94a00b`) with its
  health check passing (one failed check in the seconds before the server listened). Eight
  public pages load in headless Chromium at 1280 and 390 wide with no errors and no
  sideways scroll, and Enter App opens /stake; /stake shows live Base figures. The
  signed-in Credits panel was not opened live (it needs a sign-in). WebKit not run on the
  Mac.

## 2026-10-27 — The Stake page says what staking pays

- The Stake page now says what the staking contract actually does. A staker shares in
  Regents Labs' USDC revenue in proportion to how much of all REGENT they stake, and
  the business keeps the rest. The page used to promise "a pro rata split of all"
  revenue, which a reader takes to mean stakers get all of it. The badge reads "Plus 20%
  a year in REGENT, for now". The home page, the About page and the page list agents
  read now use the same words.
- The revenue card, now "USDC revenue", adds "Paid to stakers (lifetime)" beside the
  last seven days and the lifetime total. The stake form's preview reads "Your share of
  revenue".
- A short "How staking pays" box gives the payout formula with the contract's own
  divisor, where the revenue comes from, that USDC can be claimed at any time with no
  lock-up, the REGENT reward pool, how many of the Regent Safe's signers must agree,
  and both contract addresses with their copy icons.
- The shared staking reading adds the contract's `totalUsdcCreditedToStakers` and its
  `revenueShareSupplyDenominator` beside the figures it already read. It also asks the
  treasury Safe for `getThreshold()` and `getOwners()` at the same block. That ask is
  separate, so a treasury that is not a Safe leaves only those two figures unavailable.
  A Base reading taken before this change has none of the new figures, and the page
  shows a dash for them until the next reading, at most five minutes later.
- The share picture for /stake carries the same words (entry above). Checks:
  `platform/test/regents/staking/rpc_client_test.exs`
  (`TREASURY_SIGNERS`, `ONE_PROTOCOL_CALL`, `PINNED_SELECTORS`) and
  `platform/test/browser/stake.spec.ts`.

## 2026-10-27 — Visit lines taken out until the privacy answer

- The visit lines (`29ca02b1`, entry above) are reverted on main so the new Stake page
  words can be released now (Sean, STAKE-RELEASE 1 a). The template chief asked every site
  to keep visit lines out of production until Sean answers VISIT-SOURCES-PRIVACY. They come
  back as one commit once he answers. No database changes either way. The `logger_json`
  dependency, the privacy-page lines about visits and the checks
  `platform/test/regents_web/visit_log_test.exs`,
  `platform/test/regents_web/visit_log_page_test.exs`,
  `platform/test/browser/visits.spec.ts` and `platform/test/browser/arrivals.spec.ts` go
  with them.

## 2026-10-27 — v235 release record

- v235 runs `0a046b55`: the Stake page says what staking pays (`fe52d964`), the redrawn
  /stake share picture (`4bd54a7c`), and the visit lines taken out (`0a046b55`). The
  rollback is v234 (`f6930c94`). No database migrations in the range. Released under the
  shared-database lock (Sean, STAKE-RELEASE 1 a).
- Checked before release: server tests 577 (one property check), JavaScript 242, browser
  walk 111/111; required fixes clean against ash-template `af46cc2`.
- Live checks: one machine runs `0a046b55` (image label `main-0a046b55fc68`). Eight
  public pages (/, /stake, /about, /app, /start, /techtree, /keyfleet, /articles) load in
  headless Chromium at 1280 and 390 wide with no errors and no sideways scroll. /stake
  shows the new opening line and badge, the three revenue figures from Base (paid to
  stakers 594.32 USDC), and "How staking pays" with the 100 billion divisor, a 4.658
  billion reward pool, "2 of 3 signers" and both contract addresses with copy icons.
  WebKit not run on the Mac.

## 2026-10-27 — Visit lines back, and Global Privacy Control respected

- The visit lines (`29ca02b1`) are back: this reverts `0a046b55`. Sean answered
  VISIT-SOURCES-PRIVACY with "a", relayed by the template chief, and the change below copies
  ash-template `e61e4dd`.
- `RegentsWeb.VisitLog` reads `Sec-GPC: 1`: such a visit gets no `arrival`, and
  `VisitLog.step/2` writes nothing for it, in the request (the browser's `sign_in_opened`
  report now goes through `step/2`) and on its pages (the render context carries `gpc` into
  the LiveView's process). Its other lines are written as before.
- The privacy policy's cookies section says so; its effective date is now 27 October 2026.
- New walk in `platform/test/browser/arrivals.spec.ts` and a unit test in
  `platform/test/regents_web/visit_log_test.exs`, listed in `FEATURES.md`.

## 2026-10-27 — Sign-in and sign-out stop warning in the logs

- Sentinel's after-read of v234 and v235 saw two "Missed 1 notifications in action
  Regents.Accounts.Sessi…" warnings. Every sign-in, refresh and sign-out wrote one:
  `Regents.Accounts.SessionAuthority` ran its locked transitions in `Repo.transaction/1`,
  a transaction Ash did not start, so each `Ash.update!` inside it was left with a
  notification it could not send. It predates v234 and has nothing to do with the one
  listening connection. The transitions now run in `Ash.transact/2`; a refused transition's
  answer is wrapped so what it wrote (the seeded row, a revocation) still commits.
- `platform/test/regents/accounts/session_authority_test.exs` now fails on a missed
  notification (14 of its 17 tests fail against the old code). Its race helper holds the
  lock open inside `Ash.transact/2` too.
- The same warning comes from the shared agents library: `RegentAgents.PairedAgent`'s
  check-in calls `:touch` inside `Ash.DataLayer.transaction/2`. Handed to the template
  chief, who owns that library; the whole suite can fail on missed notifications once it
  is fixed.

## 2026-10-27 — Pair New Agent takes you straight to your agent choices

- Pressing Pair New Agent now moves you to the agent pictures in the side
  panel (the one you already chose, or else the first), so a keyboard or
  screen reader user lands right where they choose. The panel glides to the
  pictures instead of jumping, the box around them is marked for a moment,
  and the pictures settle into place one after another. Every press does it
  again.
- The Pair New Agent link on the start page now does the same once the Account
  page opens. Before, the panel opened but nothing pointed to the pictures.
- Pressed from the keyboard, or with reduced motion turned on, the panel shows
  the pictures at once and the box is simply marked for the same moment.

## 2026-10-27 — Newest Regents command line, and a way in from the home page

- The agent guides, the developer documentation and the start page's steps now
  install the newest Regents command line, 1.10.19, and the agent guide gives
  that version's published fingerprint to check the download against.
- The home page has a short line under its buttons, "Connect your agent from
  the command line", which opens the steps for connecting your agent. Agents
  reading the home page get the same pointer.

## 2026-10-27 — Menus, panels and notes stack the same way on every page

- On a phone or a narrow screen, a note under your account, such as "Sign out
  couldn't finish. Try again.", now shows over the open side panel. Before, it
  opened behind the panel and you never saw it.
- Pressing Tab first on any app page now shows a "Skip to content" link over the
  header; Enter takes you straight to the page, past the header and the menu.
- The $REGENT menu now sits flat on the page, without a soft shadow under it.
- Release record: every floating part of the site (header, side panel, phone
  menu and its shade, the account note, the $REGENT menu, the skip link, the
  Buy Credits close button and the local motion lab's panels) now takes its
  place from design-system's shared layer names, re-pinned to `804c7521`
  (design-system STYLE.md "Layers", Sean LAYERS-DEPTH a = flat), copying
  ash-template `e8ed190`. Ordering inside one picture (the world cube, the
  home hero, a book on Literature, a product tab's foil) keeps its own numbers.
  No window on regents.sh opens over another window today, so none moved to a
  popover. New checks in `platform/test/browser/layout.spec.ts`: "on a phone, the
  open menu and side panel cover the page, and the account's note sits over
  them" (fails on `8278c549`, the note behind the panel) and "the first Tab
  shows Skip to content over the header" (1280 and 390). WebKit not run on the
  Mac.

## 2026-10-27 — Every address on Stake and Redeem opens and copies in full

- Stake's "What is not circulating" window, Stake's and Redeem's Verification lists, the
  wallet each panel acts for, the notes that name a wallet when the wrong one is open, a
  sent stake for someone else (in the activity list and its receipt), the Buy Credits
  window's paying wallet and each agent under "What your agents may spend" on Account now
  show each address the way every Regent page does: a short form that opens the full
  address, a copy icon and a link to Basescan. The wallet on Stake's panel keeps its own
  letters instead of being shown in capitals.
- In the activity list, an address in a step's title keeps its usual size and colour,
  including when the step did not go through.
- A browser walk of Stake and Redeem at computer and phone widths, signed out and signed
  in, with the Buy Credits window open, now fails if any address there is printed as
  plain text.

## 2026-10-27 — Staking for someone else shows their whole address

- When you stake for a different address, the warning in its window now shows
  every character of the wallet that will receive the stake, wrapping onto the
  next line where it must, with a copy icon and a link to Basescan after it, so
  you can check it against what you meant to type.
- Once you confirm, the choice above Amount reads "Rewards go to" with the
  address on the line under it: its short form, which opens the full address,
  and a copy icon, with Change beside it. Both copy icons copy the whole
  address.
- Release record: the warning uses design-system `804c7521`'s full address form
  and the row its compact form; Stake and Redeem drop their own letter-case
  rules for addresses, which the shared component now applies itself. New
  checks: `platform/test/browser/stake.spec.ts` "Stake shows the other address
  in full in the warning and compact under Rewards go to" (signed out and
  signed in, light and dark, 1280, 390 and 320; fails on `e30cb130`) and
  `platform/test/regents_web/stake_live_test.exs` "STAKE_FOR_SOMEONE". WebKit
  not run on the Mac.

## 2026-10-27 — The warning's tick box reads clearly aloud

- In the window for staking for someone else, a screen reader now reads the
  warning's tick box as the warning itself, with the receiving address read
  once. Before, it also read out "Copy the full address" and "Open on
  Basescan" in the middle of the sentence. Pressing the warning's words still
  ticks the box, and the window looks the same.
- Release record: the warning is no longer one `<label>` around the address
  component's copy button and Basescan link; the words before and after the
  address are two labels for the box, the address sits between them, and the
  box takes the sentence as its name. The walk "Stake shows the other address
  in full in the warning and compact under Rewards go to" now also fails on any
  button or link inside a label on /stake and on any other name for the box
  (both fail on `cc8c5613`). WebKit not run on the Mac.

## 2026-10-28 — Visit lines and the sign-in log fix held back for Sean's answer

- The visit lines with the Global Privacy Control rule (`59154547`) and the sign-in log
  fix (`38a95149`), both entries above, are taken out of this release so the ordinary work
  above them can go out now. Both touch areas that wait for Sean's letter (VISITS-RELEASE).
  They come back as one revert of this commit once he answers. No database changes.

## 2026-10-28 — v236 release record

- v236 runs `ac923423`: Pair New Agent points to the agent choices (`810864f3`),
  regents-cli 1.10.19 on every agent page and the home page's command-line line
  (`8278c549`), design-system `804c7521` with the shared layer places and the "Skip to
  content" link (`75915c59`), every address on Stake and Redeem drawn with the address
  component (`50c1dfcd`, `e30cb130`), the full and compact address forms on Stake
  (`cc8c5613`, `7a5baeba`), and the visit lines and sign-in log fix held back
  (`ac923423`). The rollback is v235 (`0a046b55`). No database migrations in the range.
  Ordinary release under AUTONOMY-RULE a, under the shared-database lock.
- Checked before release: server tests 578 (one property check), JavaScript 242, browser
  walk 121/121; required fixes clean against ash-template; command list ok against
  regents-cli `02f89615`.
- Live checks: one machine runs `ac923423` (image label `main-ac923423d139`), /healthz
  200. /, /stake, /redeem, /account, /start and /docs load in headless Chromium at 1280
  and 390 wide with no page errors and no sideways scroll; the home page shows "Connect
  your agent from the command line"; the first Tab on /stake and /account shows "Skip to
  content"; no address on those pages is printed as plain text. WebKit not run on the Mac.

## 2026-10-27 — An agent asking who it is gets its answer again

- An agent asking Regents who it is (`regents protocol agents whoami`, or the
  regents_agent_whoami tool) gets its answer again, instead of an error. The answer says
  whether it is paired, what it may do here in that state and its next step: reading the
  public pages and docs; once paired, also reading its person's account, name claims,
  staking position, Credits and Points. It never uses the wallet, changes the account,
  pairs other agents or spends Credits.
- The published API description (`/openapi.json` and `/api-contract.openapiv3.yaml`) now
  describes that answer as it really is: `status`, `allowed` and `next_step`, with no
  `effective_access` field. An agent checking the answer against the description no longer
  finds a mismatch.

## 2026-10-28 — Visits counted, quieter sign-in, and agents can ask who they are

- regents.sh counts its own visits again, so we can see which pages people find and use.
  A browser that sends Global Privacy Control is never counted that way. The privacy
  policy says so, and its effective date is now 28 October 2026.
- Signing in, refreshing and signing out no longer leave a warning in the site's logs.
- Release record: brings back `59154547` and `38a95149` by reverting `ac923423` (Sean,
  VISITS-RELEASE a, 28 Oct 06:58Z), with the privacy date moved to the release day, and
  ships the who-am-I fix and its published description (Sean, WHOAMI-FIX a).

## 2026-10-28 — v237 release record

- v237 runs `16454a74`: whoami answers again with the template-shaped `allowed` config
  (`dd73f5ae`) and its real answer shape in the API contract (`df18636d`); the visit
  lines and the sign-in log fix return, with the privacy effective date moved to 28
  October (`16454a74`). The rollback is v236 (`ac923423`). No database migrations in the
  range. Sean's letters 28 Oct 06:58Z: WHOAMI-FIX a and VISITS-RELEASE a; Sentinel asked
  for main to ship 07:10Z. Released under the shared-database lock.
- Checked before release: server tests 591 (586 tests, five property checks), JavaScript
  242, browser walk 127/127; required fixes clean against ash-template `e9a5fba`; command
  list ok against regents-cli `02f89615`.
- Live checks: one machine runs `16454a74` (image label revision), /healthz 200; a signed
  whoami from a paired agent answers `paired` with its allowed list, an unsigned one
  answers 401 with the missing headers; /privacy shows October 28, 2026; arrival lines
  appear in the logs; /, /privacy and /stake load in headless Chromium at 1280 and 390
  wide with no page errors and no sideways scroll. WebKit not run on the Mac.

## 2026-10-28 — The home page in two columns of panels

- The home page now reads as two columns of flat panels under the same header,
  one column shorter than the other. The first holds the mission in one sentence
  and the four products, each with its drawing on a tile of its colour, what it
  does in a line and a link to its site. The second holds how it works (one
  sign-in for agents, WebMCP Tools and regents-cli, staking $REGENT for a share
  of the lab's USDC revenue), three principles, and the hero with its cube as
  the third panel. On a phone the panels stand in one column, the shorter
  column's panels first.
- The hero keeps everything it had: Enter App, WebMCP Tools, the command-line
  line, the six worlds and the cube, now in the middle of its own panel. The
  words sit above the cube's stage instead of over it.
- The copy of the home page that agents read says the same things in the same
  order as the page.
- Release record: panels are design-system sheets (`Regent.Structure.panel`,
  four cut corners) on the page ground; the product cards and the how-it-works
  steps are cards ruled off on their sheet. The cube's stage now follows the
  width of its panel rather than the window. Browser checks updated where the
  layout changed: the hero's words above the stage, the worlds' rows read from
  the hero's width, and the hero scrolled into view before its checks. No
  database changes. WebKit not run on the Mac.

## 2026-10-28 — Redeem and Stake fit the narrowest phones

- On Redeem, the first button now reads "Connect wallet", so it no longer runs
  out of room on a 320-wide phone.
- On Stake, below 360 wide the Buy and chart links each take their own row
  instead of cutting their words short.
- Release record: redeem_live.ex intro button label; stake.css one-column token
  links under 22.5rem; the Redeem browser check now finds the intro button
  inside its own actions, since the connect panel has a button of the same
  name. Checks: 591 Elixir, 242 TypeScript, 127 browser, all passed. No
  database changes. WebKit not run on the Mac.

## 2026-10-28 — v238 and v239 release record

- v238 runs `d58a8dbc`: the home page in two columns of panels, the hero third in the
  second column. Rollback v237 (`16454a74`). No database migrations. Sentinel 07:46Z read
  v238 healthy: signed who-am-I works, unsigned refused, no errors kept.
- v239 runs `d791de80`: the Redeem intro button reads "Connect wallet", and the Stake token
  links take a row each below 360 wide. Rollback v238 (`d58a8dbc`). No database
  migrations.
- Checked before v239: server tests 591 (586 tests, five property checks), JavaScript 242,
  browser walk 127/127.
- Live checks on v239: the machine's image label is `d791de80`; headless Chromium on
  /redeem and /stake at 320 and 390 wide shows no sideways scroll and no cut-off button
  or link; the Redeem intro button reads "Connect wallet"; the Stake Buy and chart links
  stack at 320 and sit side by side at 390. WebKit not run on the Mac.

## 2026-10-28 — Agent skill: picking a product and checking back

- /skill.md now helps an agent pick the right Regent product for its person's goal
  (`regents protocol products list` or `regents_products`), lists every account read
  beside its command and browser tool, and says how often to check back: account, name
  claims and Points daily, Credits before each spend decision, staking daily and once
  after the person acts.

## 2026-10-28 — A browser that asks not to be tracked starts no visit

- When a browser sends Global Privacy Control, the site sets no visit cookie and none
  of its pages, tool calls or reports carries a visit, so nothing groups its activity
  into one visit. Before, only the lines for where a visit came from and how far it got
  were left out; the visit itself was still kept.

## 2026-10-28 — v240 release record

- v240 runs `787b0e05`: a browser that sends Global Privacy Control starts no visit (no
  `_visit` cookie, no visit on its pages, tool calls or reports), and the agent skill page
  update `db98e9c3` from another lane. Shipped on its own ahead of the template rollout,
  on Sean's 08:24Z answer. Rollback v239 (`d791de80`). No database migrations.
- Checked before v240: server tests 592 (587 tests, five property checks), JavaScript 242,
  browser walk 125/127 with the other two passing on a rerun (load timeouts, machine load
  about 240), required fixes all present.
- Live checks on v240: the machine's image label is `787b0e05`; headless Chromium over /,
  /stake and /redeem gets the `_visit` cookie and the visit tag without Global Privacy
  Control, and neither with it. WebKit not run on the Mac.

## 2026-10-28 — The site says which version it runs

- Agents and site checks read the browser tool list at `/capabilities.json`, which now
  also names the commit and release this site runs, the same way every Regents site
  does. `/capabilities` is gone.
- The check-in command is `regents protocol agents status`, the name the other Regents
  sites use; `agents me` is gone.
- Release record: `build` comes from `SOURCE_COMMIT` and `FLY_IMAGE_REF` at boot
  (`config :regents, :build`), following ash-template's capabilities document and
  control rollout 2026-10-28-live-commit. The served document stays the tool manifest
  plus `build`; the template's per-operation rows are not adopted here. OpenAPI and
  YAML contract move to 4.0.0. No database changes.

## 2026-10-28 — Home page review fixes

- Keyboard users reach the six "Visit" links in the cube, and the list shows as soon as
  one of its links has focus, even before the cube has drawn.
- The home page has a "Skip to content" link, as every other page does.
- Keyfleet is shown as available now, and the "One token, not equity." principle names
  Keyfleet beside Autolaunch and Patchbay as sending part of what it earns to stakers.
- With less motion asked for, or without scripts, the list of worlds on a narrow stage
  shows in full instead of scrolling inside its box.
- Release record: from the adversarial review of v238. world_cube.css hides the
  not-yet-drawn list with opacity only (no `visibility: hidden`), shows it on
  `:focus-within`, and lets the narrow stage grow under `prefers-reduced-motion:
  reduce` or `scripting: none`; home_live.ex adds the skip link and `main#home-content`,
  marks the three Keyfleet items live and updates the principle. Kept as they were:
  the shared footer's "What agents can do here" label (the template chief is
  renaming it on every site at once) and the narrow cube layout inside the
  desktop hero panel.

## 2026-10-28 — Review fixes before the next release

- A browser that asks not to be tracked also loses a visit cookie it was given earlier.
- Request limits no longer fail for some callers; a stuck limit had refused them with an error.
- The cube's list of worlds can be clicked once a keyboard has shown it.
- Keyfleet's three rows on the home page link to its live pages.
- Keyfleet's browser tools are read from the address Keyfleet now uses.
- The Buy Credits window and the book tips sit flat on the page, with a border and no shadow.

## 2026-10-28 — Agents install the newest command line

- The start page, agent guide, docs and llms.md point agents at regents-cli 1.10.20,
  which reads agent status with `regents agents status`.
- The web server moves to Bandit 1.14.1, which closes a memory-use weakness in how it
  reads uploads sent in many tiny pieces (EEF-CVE-2026-116078), as ash-template did.
- Release record: v241 = review fixes 9a4c815b..21a1eeea plus this pin. agent_start.ex,
  agents.md (source commit 0e3768f5b92fe8210fb00fea0053bcb5e9c2afaf, wheel SHA256
  55b242b41a86e4bd1952e1edb93e31e5cd718186e735867d4b276243f96179ad), docs.md, llms.md
  and the Makefile's REGENTS_CLI_REV move from 1.10.19. No database changes. Rollback:
  v240 787b0e05.

## 2026-10-28 — Newest shared sign-in and wallet library

- Each agent keeps its own key folder, and an agent's check-in no longer loses its notifications.
- Every Stake and Redeem wallet step ends with Regent's Base builder code, so Base credits Regent for it; the contracts ignore it.
- The Credits card purchase table comes with the library, as on every Regents site; buying Credits by card stays off.
- Correction to "Review fixes before the next release": Keyfleet's three rows on the
  home page never showed links. The home page's Keyfleet room and the /keyfleet page
  draw their own panes, so the three links were in data no page draws. They are
  removed; Keyfleet's rows still read "Available now".
- Release record: v242 = elixir-utils 14013e42 (template v124's pin) on v241 206f8c1f,
  with step and release tests following it and a two-minute limit on the twelve-state
  Stake walk. The library's Credits change `20261027170554_card_purchases` is a shared
  change: Sean's "2. a" (28 Oct 15:45Z) allows checking for the table and adding it
  only if missing. Rollback: v241 206f8c1f.

## 2026-10-28 — Regents v241 and v242 released

- v241 (`206f8c1f`) went live as Fly v241 at about 17:28Z: the review fixes, agents
  on regents-cli 1.10.20 and Bandit 1.14.1. The rollback is v240 (`787b0e05`).
- v242 (`599de2bb`) went live as Fly v242 at about 17:43Z: elixir-utils 14013e42 on
  Sean's "1. a" (28 Oct 15:45Z). The rollback is v241 (`206f8c1f`).
- The release step (`/app/bin/migrate`) succeeded, so the shared Credits change
  `20261027170554_card_purchases` was already in production's ledger;
  `migrate-shared` was not run and was not needed (Sean's "2. a" allowed it only if
  the table was missing).
- Before release, on each commit: 593 server tests, 242 script tests, 127 browser
  tests, required fixes clean.
- Live checks after each release: one machine on the new image with its health check
  passing; `/capabilities.json` reports the commit; `/`, `/stake`, `/redeem`, `/docs`,
  `/app` and `/start` load in headless Chromium at 1280 and 390 wide, light and dark,
  with no errors and no sideways scroll. WebKit not run on the Mac.

## 2026-10-29 — Account menu, and Chrome's WebMCP trial

- The account's button at the top right opens a small account menu on every page,
  as on every Regent site: the person's picture, name and wallet, their three most
  recently active agents with Manage, Pair New Agent, Manage Account and Sign out.
  It replaces the side panel, and the cookie that remembered whether the panel was
  open is gone.
- The Account page takes the layout every Regent site shares: the names and
  connected accounts first, then the account card and the agents, then Pair New
  Agent beside Credits and the account's details. Pair New Agent is there and
  nowhere else; every Pair New Agent link, the menu's and the start page's included,
  leads to it, and the keyboard starts on the agent choice.
- On a phone, the open navigation menu leaves the page behind it still. On the
  narrowest phones the Credits balance moves from the header into the account menu.
- Sign out closes the account menu, so a note saying it couldn't finish shows under
  the account button instead of behind the menu.
- Every guide, tool description and error hint that sent agents' people to the side
  panel now sends them to Pair New Agent on their Account page.
- Every page and answer carries Chrome's WebMCP origin-trial token for
  https://regents.sh (valid until 30 Mar 2027), so Chrome lets browser agents use the
  tools regents.sh's pages offer.
- Claude Duet's picture shows for Claude agents, from design-system 3134bab0.
- Libraries: design-system 3134bab0, elixir-utils 9da44bdc (no database changes).

## 2026-10-29 — Agent parity table

- Add docs/agent-parity.md: every action a person can do on regents.sh, with its five agent
  surfaces (page, WebMCP, hosted MCP, Claude connector, CLI) and the gap for each
  missing one (39 actions, gaps R1 to R16). Docs only; nothing on the site changes.

## 2026-10-29 — Regents v243 released

- v243 (`b0630139`) went live as Fly v243 at about 08:46Z: the account menu, Chrome's
  WebMCP trial token, Duet's picture and the agent parity table. No database changes.
  The rollback is v242 (`599de2bb`).
- Before release: 596 server tests, 242 script tests, 138 browser tests, the CLI
  command check and required fixes (ash-template cb75f6be) clean.
- Live checks after release, headless Chromium at 390 and 1280, light and dark:
  `/`, `/stake`, `/account`, `/start` and `/docs` load with no errors, no sideways
  scroll and no side panel, and every one carries the `origin-trial` token and
  `permissions-policy: tools=(self)`. Duet's picture is served. The signed-in menu and
  the Duet tile were not checked live (that needs a sign-in). WebKit not run on the Mac.

## 2026-10-29 — Account is the same page on every Regent site

- `/account` is now the shared Account page every Regent site has, starting in
  ash-template: your profile, your Credits, your agents and Pair New Agent, and your
  public display name, which you can now change from the page.
- Account has five tabs: Account, Points, Credits, Wallets and Connections. Wallets and
  Connections each have their own page (`/account/wallets`, `/account/connections`).
- Your Regent names and claiming a new one move to their own page, `/names`, in the
  left menu.
- What your agents may spend moves to the Credits tab, under the history.
- An agent's picture is set in its window on the Account page, as before.
- Libraries unchanged: design-system 3134bab0, elixir-utils 9da44bdc (no database
  changes).

## 2026-10-29 — Chain reads that fail are counted for Sentinel

- Every chain read that gets no answer (a node error, a refused request, a timeout or a
  dropped connection) is now counted on the private metrics listener as
  `health_chain_request_failures_total`, by method, kind of failure, chain and the part
  of the site that asked (`wallet`, `wallet_steps`, `staking`, `points`, `redemption`),
  in the same words as ash-template. Sentinel reads it beside the other health numbers.
- regents.sh sends nothing from a wallet of its own, so it reports no unconfirmed sends.

## 2026-10-29 — Agent refusals link to their help page

- An agent refused as `agent_not_paired` or `person_not_here` now reads
  "Help: https://patchbay.help/errors/<code>" at the end of the hint, at check-in and
  at every other signed request, in the same words as ash-template (2362ad83). The
  contract examples say the same.
- Libraries: elixir-utils 9539469f (the check-in refusals), no database changes.

## 2026-10-29 — Regents v245 and v246 released

- v245 (`7912758d`) went live as Fly v245 at about 18:42Z: chain reads that fail are
  counted for Sentinel. The rollback is v244 (`5bdfc471`).
- v246 (`e5c36148`) went live as Fly v246 at about 18:50Z: agent refusals link to their
  help page, elixir-utils 9539469f. The rollback is v245 (`7912758d`). No database
  changes in either.
- Before release: 600 server tests, 252 script tests, 139 browser tests (one Redeem walk
  timed out under load in the v246 run and passed three times out of three alone), the
  CLI command check, identity and required fixes (ash-template 74403fb1) clean.
- Live checks after release, headless Chromium at 390 and 1280: `/`, `/stake`,
  `/account`, `/names`, `/redeem` and `/docs` load with no errors and no sideways
  scroll; `/openapi.json` carries both help links. A refused agent request was not sent
  live (that needs an unpaired agent's signature). WebKit not run on the Mac.

## 2026-10-29 — Regents Cloak pages

- New `/cloak` page: "The private agent stack, ready to run." Download for Mac stays
  off with "Coming soon" beside it until the first signed release exists; Set up with
  your agent opens the guide. Six protections are shown as Planned, with the limits
  beside them.
- New `/cloak/guide`: the setup steps an agent follows, what only the owner does
  (macOS prompts, funds, recovery, new files or tools), the rules and the limits. Agents
  get the same guide as Markdown at the same address. Install commands arrive with the
  first signed release.
- Cloak joins Products in the side panel, the sitemap and llms.txt. No database
  changes.
