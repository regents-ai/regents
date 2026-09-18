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
