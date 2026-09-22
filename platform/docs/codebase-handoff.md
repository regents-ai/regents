# regents.sh — handoff

For a coding agent picking up this codebase. Everything here was checked against
the repository and the running site on 2026-09-03, at `main` = `0a82684`.

---

## 1. What this is

`ash-platform` is the Elixir/Phoenix application behind **https://regents.sh**. It is
deployed on Fly.io as the app **`regents-sh-web`**.

Four public surfaces are open today:

| Route | What it is |
| --- | --- |
| `/` | The marketing home page, with the WebGPU hero |
| `/stake` | REGENT staking against the Base contract |
| `/redeem` | Animata I / II → Regents Club membership + REGENT vest |
| `/app` | The signed-in Regent shell |

Autolaunch and Techtree have left this app (see §9); their product copy on `/`
and `/stake` stays, linking out to autolaunch.sh and techtree.sh.

Stack: Phoenix 1.8 · LiveView 1.2 · Ash 3.33 · AshPostgres · Privy for sign-in ·
Base (chain 8453) for every on-chain figure.

---

## 2. Environment

- Application root: `/Users/sean/Documents/regent/repos/regents/platform`.
- Set `REGENT_DEPS_ROOT` to the selected shared repository root; package paths and
  component checks are documented in the current README and `mix.exs`.
- Follow the workspace `regent-workflow`. Use ordinary Git worktrees for concurrent
  writers, unique ports and disposable test databases. Historical ticket paths and
  reserved-port lists are no longer current assignments.
- Preserve unrelated working changes. Never use bare `git stash` / `git stash pop`
  across concurrent writers; a repository's stash stack is shared.

**A fresh worktree needs both** `mix deps.get` **and** `npm ci` before anything runs,
and `mix assets.build` before any browser test.

---

## 3. How the app is shaped

### The shell and the route catalog

Almost every signed-in route is one LiveView — `AshPlatformWeb.ShellLive` — switching
on a `live_action`. What each route *is* (its label, sidebar, header controls,
background, search behaviour, allowed parameters) is declared in
**`lib/ash_platform_web/route_catalog.ex`**, not scattered through the shell.

Adding or removing a route means touching three places together:
`router.ex`, the `@entries` list and the `@specs` map in `route_catalog.ex`. A route
present in one and absent from another fails `mix ash_platform.route_handoff --check`,
which runs in the gate.

`/` (`HomeLive`), `/stake` and `/redeem` render through the shell's stake/redeem page
components; the home page is its own LiveView.

### The launch gate

`AshPlatformWeb.Plugs.LaunchGate` closes every non-marketing surface when
`app_surfaces` is off. It is read per request from config set in `config/runtime.exs`,
so a Fly secret flips it without a rebuild. The marketing page and signing out stay open either way.

### Reading the chain — the part to understand before editing

This is the most opinionated code in the repo and the easiest to get wrong.

- **The manifest is the authority.** `contracts/base-mainnet.json` pins every address,
  every read, every prepared action and its selector. `contracts/chain-contracts.yaml`
  pins a SHA-256 of that file; change the manifest and you must repin the digest, or
  `test/ash_platform/wallet_actions/manifest_test.exs` fails.
- **Selectors are proved at compile time.** `wallet_actions/abi.ex` and
  `redemption_abi.ex` declare each locally encoded selector and assert in
  `__after_compile__` that its signature exists in the pinned ABI JSON. A typo'd
  selector fails the build, not production.
- **One block owns a whole reading.** Reads go through multicall3 `aggregate3`, pinned
  to a specific block hash with `requireCanonical: true`. A page never pairs one
  block's balance with another block's allowance. Where a second aggregate is
  unavoidable (the treasury has to name itself before you can ask what it holds), it
  is sent against the same pinned block.
- **`ownerOf` is read alone.** It legitimately reverts for a token that does not
  exist, and under `allowFailure: false` that would take the whole aggregate down.
- **Staking pages never call Base on page load.** `Staking.SnapshotCache` is a
  GenServer holding one shared reading for everyone; a page paints it instantly.
  Only a signed-in visitor can ask for a new one, rate-limited, and the refusal path
  leaves the previous good reading exactly where it was. If you add a figure to the
  staking page, it belongs *inside* that snapshot, not in a per-request read.
- Circulating REGENT is computed in `staking/supply.ex` as total supply less the
  treasury, the Animata redeemer, the staking contract's own reward inventory, and a
  hardcoded 40 billion Clanker vault. The Clanker figure is the one number on the
  page not read from chain, by founder decision.

### File map

```
lib/ash_platform/
  staking/        snapshot cache, rpc_client, facts, supply arithmetic
  redemption/     rpc_client, actions, snapshot
  wallet_actions/ abi.ex, redemption_abi.ex, rpc.ex, envelope, observer
  formation/      regents, agent links, cloud runtimes
lib/ash_platform_web/
  route_catalog.ex   the route allowlist and its behaviour metadata
  live/shell_live.ex the one shell LiveView (large; read the region you need)
  live/home_live.ex  the marketing page
  live/stake_live.ex live/redeem_live.ex
  token_links.ex     the Uniswap and DexScreener links, built from the pinned
                     token address so a link can never name another token
assets/css/pages/    one stylesheet per surface
assets/js/hooks/     LiveView hooks; home_prism is the WebGPU island
contracts/           the pinned manifest, its digest, and the ABIs
test/browser/        Playwright specs (real browser, port 4002)
```

---

## 4. Gates — run all of these before claiming anything works

Run `make check-platform` from the repository root; the README's "Checks" section says
what it covers. For browser behaviour, also run:

```bash
mix assets.build && npx playwright test test/browser/<spec>.spec.ts
```

**First run in a new worktree** needs its partition database; follow the README's
"Checks" section.

For asset-budget checks, run `mix compile` in dev first — `mix esbuild --minify`
fails on unresolved `phoenix-colocated/ash_platform` until the colocated hooks exist.
Afterwards restore with `mix phx.digest.clean --all && mix assets.build`.

---

## 5. Releasing to production

`fly.toml` **has no `app` field**, so `-a regents-sh-web` is mandatory on every fly
command, and the file is not copied into the build context by the context script —
copy it in by hand.

```bash
scripts/build-release-context.sh <context-dir> amd64
cp fly.toml <context-dir>/fly.toml
cd <context-dir>
fly deploy -a regents-sh-web --build-only --push --remote-only --image-label main-<sha>
fly deploy -a regents-sh-web --image registry.fly.io/regents-sh-web:main-<sha>
```

The release runs `/app/bin/migrate` before boot, so any migration you add ships and
runs automatically.

**Known debt:** the sealed offline supply is pinned to the lockfile from 2026-08-12
and has drifted, so the context script's lockfile checks refuse the current lockfiles
until the supply is resealed. Reseal it rather than working around the checks.

**Verify live in a real browser, not by trusting the deploy output.** The in-app
browser pane reports `document.hidden === true`, so animation and WebGPU look dead in
it even when they work. Drive a headed Playwright Chromium against https://regents.sh
instead. Use `waitUntil: "domcontentloaded"` — `networkidle` never settles because of
the LiveView socket.

---

## 6. Rules that are not negotiable

Follow the founder rules in `/Users/sean/Documents/regent/AGENTS.md`.

---

## 7. Recently shipped (context for what you'll see)

- `e1f1d9c` — circulating REGENT computed live per snapshot and shown in the hero;
  the "USDC Revenue Sources" accordion above the contract position.
- `ad10585` — Buy REGENT → Uniswap, new View Chart → DexScreener, both moved under
  the lede; /redeem lede reworded.
- `0a82684` — /redeem cards now show "Remaining Passes" from each collection's own
  supply and "Regents Club Passes claimed: N / 1,998"; the contract position panel is
  no longer `position: sticky`, which had made it slide over the revenue card on
  scroll.

---

## 8. Traps that have already cost time

- `Application.get_env(app, key, default)` returns a **stored `nil`** rather than the
  default. Restore test config with `Application.delete_env`, never by putting `nil`.
- The Bash working directory persists between commands and silently drifts;
  `package.json` is at the repo root, not in `assets/`.
- Playwright failing en masse on `[data-hero-enhanced]` almost always means the
  worktree has no built assets — run `mix assets.build`.
- Changing `contracts/base-mainnet.json` breaks two pinned tests until you repin:
  the evidence SHA-256 in `chain-contracts.yaml`, and the explicit interface id lists
  in `test/ash_platform/contracts/chain_manifest_test.exs`.
- The machine has filled its disk more than once. `uv cache clean` reclaims ~79 GB
  safely; Docker's VM has held 131 GB. A full disk knocks Postgres into recovery mode
  and every command fails with `ENOSPC` until space is freed.

---

## 9. Open work

**Techtree has left this app.** The vertical, its routes, OpenAPI
paths, comment reactions, and the `techtree` schema tables are gone. Product copy
on `/` and `/stake` stays — Techtree is still a business and still a revenue source.

**Autolaunch has left this app.** Founder decision, 2026-09-18: remove it. The in-app
pages, the `/api/autolaunch/v1/*` endpoints, the Base log indexer, comments and the
retained Autolaunch contract interfaces are gone; autolaunch.sh is the product. The
`autolaunch_app` tables belong to the Autolaunch site and were never migrated from
here. The empty `regents_app.comments` table was dropped on 2026-09-19. Read-only
`/autolaunch`, `/techtree` and `/patchbay` information pages are briefed in the
workspace `docs/backlogs/regents.md`.

**Other open work:** reseal the release supply; a common-sense audit of every
interaction; a stray "Missed 1 notifications" warning from
`SessionAuthority.bind/revoke`.

**Unanswered by the founder:** whether the standing authority extends to production
releases, and what to do about the machine's disk (Docker VM 131 GB, huggingface
cache 19 GB).
