# ash-platform founder shell and first protected capabilities

Status belongs to the current Hermes assignment. This document records founder-approved product and architecture truth for the independent `ash-platform` application.

## Outcome

Build a small Phoenix, LiveView, and Ash application with no runtime or code dependency on `platform/`. Phase 1 proves the public homepage, exact route catalog, persistent product shell, and the behavior seams that Design and later capability slices consume. The first locally testable product milestone then adds three narrowly researched close-ports: browser-human Privy sign-in, REGENT staking, and NFT-to-REGENT redemption.

Epic: `regent-2mf0`. Phase 1: `regent-2mf0.1` through `.5`. Protected capabilities: Privy `.6`, staking `.7`, redemption `.8`.

## Binding clean-room rules

- Admission is allowlist-only. An unapproved capability, route, field, dependency, or old implementation is absent.
- Work is sliced vertically by playable Ash capability. There is no horizontal layer-completion or later consumer-cutover stage.
- Do not create an Ash resource before a real approved product state owner exists.
- The first authenticated resource is deny-by-default. Actors are supplied while building queries, changesets, and actions. Human Privy and SIWA agent principals never share an auth rail.
- One canonical human/agent identity model has one physical state owner. Other capabilities consume named domain interfaces.
- Add only used dependencies, use latest stable releases, exclude prereleases, lock exact resolutions, record official-source evidence, and run supported outdated/security audits.
- Set and test early budgets for JavaScript, CSS, rendered page weight, animation stability, and query counts.
- First-shell proof covers persistence, deep links, cancellation/latest-destination-wins, keyboard use, reduced motion, responsive behavior, accessibility, loading, and failure isolation.
- `platform/` is quarantined evidence. Only targeted Privy, `/stake`, and `/redeem` reconnaissance is approved; copying unrelated architecture is forbidden.
- No production database connection until the four protected datasets have an explicit relationship and authorization map. Phase 1 has no Repo, database config, migration, or DB reads/writes.
- No compatibility adapters, shared Ecto contexts, old migration replay, dual shapes, production calls, deploy, push, server signing, or live value movement.

The four protected datasets for later deliberate work are `platform.platform_human_users`, `platform.basenames_mints`, `platform.basenames_mint_allowances`, and `platform.basenames_payment_credits`. Phase 1 does not connect them.

## Exact initial route allowlist

Outside the shell: `GET /`.

Inside one persistent shell: `/app`, `/formation`, `/regents/:slug`, `/techtree`, `/techtree/nodes/:node_id`, `/techtree/:tree_slug`, `/autolaunch`, `/autolaunch/auctions`, `/autolaunch/auctions/:auction_id`, `/autolaunch/tokens`, `/autolaunch/tokens/:token_id`, `/autolaunch/create`, `/stake`, `/redeem`.

The node-detail route precedes the generic tree route and `nodes` is never a valid tree slug. No other product route is admitted.

The four app identities are Formation, displayed as Nous Portal, Autolaunch, Techtree, and Regent Ops, displayed as Regents Labs. The app selector always opens `/formation`, `/autolaunch`, `/techtree`, or `/app`. Public records and signed-in workflows use the same shell; authentication changes actions, not page architecture.

Techtree has exactly five root datasets: GeneBench-Pro Reference Lab, Question Forge Metaskills, New Question Candidates, BixBench Capsule Lab, and Skill Training Lab. Map and List are local presentations on one tree route. Initial web Techtree has no publishing or paid-payload capability.

## Route metadata contract

`AshPlatformWeb.RouteCatalog` is the sole owner. Each route exposes path pattern, LiveView action, parameter schema, reserved values, route id, app id, app display label, page label, canonical root, sidebar model, header controls, search kind, background slot, content transition kind, scroll policy, and local state.

Sidebar targets are typed as route targets, Techtree tree/presentation targets, or the auth-neutral viewer profile. Header controls use the closed set: search, filters, view switcher, wallet status, network status, and profile actions. Search exists only in Autolaunch and Techtree.

Route metadata is behavior authority, not presentation. It is exported once as generated Design handoff JSON plus a digest.

## Persistent shell behavior

One ShellLive owns all inside-shell routes. It has one internal scroller; the document body does not scroll. Desktop header/sidebar are fixed; mobile has a full-feature contextual menu. New routes, app roots, Back, and Forward start at the top; scroll offsets are not restored. Same-tree Map/List changes do not create history or reset scroll.

Content work is supervised and generation-tagged. A newer destination cancels and supersedes old work. Stale results and exits cannot replace the active destination. Direct/deep loads render the correct shell immediately. Header, navigation, theme, and app switching remain usable while the main region loads or fails.

Theme persistence exposes System, Light, and Dark through a small local-storage seam. Motion consumes metadata but owns no navigation or product state. Reduced motion is immediate.

## Design ownership handoff

After the immutable scaffold commit, Design owns only the declared presentation paths: homepage template/page CSS/page hook/hero destination/test; shell component and presentation children/shell CSS/render tests; shared motion hooks/tests; theme menu and material tokens; eight background slot assets/manifest/component; and `docs/design/founder-shell/**` evidence. Ash retains router precedence, LiveView/session topology, route metadata, access and identity resolution, content lifecycle, capability state, and behavior hooks.

The shell presentation uses high-opacity gradient-fill/gradient-stroke glass with 0–4px geometry. General controls are square, never pills. There is no shell footer.

The approved homepage hero source is external input only until Design receives ownership: `/Users/sean/Downloads/hero-bg-dark.svg`, SHA-256 `5d04f865bb1b4611e6c9cf9d44e2377107202782b27064e864fd2c4509e0da8c`.

## Quality gates

- exact 15-page router/catalog equality and route precedence
- persistent shell and document identity across navigation
- deterministic cancellation, error/crash isolation, history, local-state, keyboard, reduced-motion, 320px mobile, and accessible landmark tests
- zero database queries; forbidden Repo/database/old-platform dependency checks
- JavaScript at most 175 KiB gzip, CSS at most 60 KiB gzip, fixture HTML at most 100 KiB uncompressed
- `mix compile --warnings-as-errors`, focused/full tests, formatting, `mix ash.codegen --check`, TypeScript/Vitest/Playwright, dependency outdated/audit checks, `git diff --check`
- exact ownership manifest convergence before commit

## Protected follow-on milestone

Privy, staking, and redemption each receive targeted old-platform behavior/test custody, contract-first design where public behavior requires it, TDD, policy/auth or wallet-action mutations, independent review, and a narrow commit. Browser Privy humans and SIWA agents remain distinct. All staking/redemption value actions are prepared for user signing; the server never signs or moves value. `/redeem` is NFT-to-REGENT only. `/stake` supports stake, unstake, claim USDC, claim REGENT, and manual claim-and-restake; automatic restaking is absent.
