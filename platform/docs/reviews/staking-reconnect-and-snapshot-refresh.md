# Staking wallet reconnection and snapshot freshness

## Scope and live observation

Sean reported on `https://regents.sh/stake` that Disconnect → Sign In restored the ENS account label but not the staking wallet, and the subsequent Connect Wallet step replaced the page. A read-only browser inspection also confirmed `Confirmed at Base block #50,882,774, read 76 hours ago.`

The fixes below are local and uncommitted. No production deployment, wallet signing, production database change, or credential-file read was performed. The live site has not been repaired by these local edits alone.

## Changes

- Wallet login records a short-lived, tab-local selection hint before a possible authentication document transition. Once wallet hooks hydrate, the bridge matches the choice to exactly one connected Ethereum wallet and sets Privy's active wallet. Privy retains ownership of long-lived selection persistence. The hint is not server authority, and an absent/ambiguous wallet is not replaced with the first connected wallet.
- Successful wallet connection explicitly republishes wallet state even if React does not render again. The authenticated sign-in fast path clears the disconnected flag before the successful session transition; ordinary passive startup does not clear it.
- Signed-in Stake and Redeem connection buttons use the connection-only path, not another sign-in. Existing LiveView wallet events load the position. Protected transaction authorization and wallet confirmation remain unchanged. Actual login/logout session transitions still use the existing document-replacement boundary.
- Staking controls enter with a 180 ms animation; reduced motion disables it. The browser check asserts the document time origin is unchanged during signed-in wallet connection.
- Shared protocol snapshots refresh every 60 seconds without requiring a visitor. Periodic and manual refreshes share the existing rate budget and one in-flight reading. Timers are rearmed after failures, obsolete timer messages are ignored, and the last good snapshot and its original timestamp survive failed reads. Price quotes remain separately bounded by their existing 120-second freshness interval.
- An existing authentication browser test referred to intentionally disabled Settings. It now verifies session stability through supported live navigation to Stake rather than restoring Settings or weakening authorization.

## Verification

- `mix precommit`: 1,134 tests, zero failures, one external exclusion; compile, formatting, Credo, Sobelow, xref, codegen and route handoff passed.
- `npm run typecheck`: passed.
- `npm test`: 505 tests passed.
- `npm run test:budgets`: 2 tests passed.
- Existing `stake.spec.ts`, `redeem.spec.ts`, and `u3_auth_lazy_acceptance.spec.ts`: all 42 browser checks passed after the final changes.
- Red-to-green regressions exercised actual captured AccountBridge callbacks, delayed wallet hydration, unchanged-render connection completion, and authenticated fast-path reconnection. Cache tests exercise timer scheduling, shared rate limits, in-flight coalescing, failed-read recovery, stale timer rejection, and quote refresh.

Browser wallet/provider and chain responses were deterministic local fixtures, not a real Zerion sign-in. The remaining real-provider canary is Disconnect → Zerion sign-in → restored position → reload persistence on the approved deployed origin.

## Evidence and release boundary

Logs:
- `/tmp/regents-wallet-and-snapshot-precommit-final.log`
- `/tmp/regents-wallet-and-snapshot-browser-final.log`

Tests used owned local partitions `_astra_831_review` and `_7f3a9c1e5b2d`; browser port 4002. No unrelated server was stopped. The test environment disables the background refresh timer except when the cache regressions explicitly drive it.

Production deployment still requires Sean's approval. Do not deploy this entire dirty checkout indiscriminately: it also contains earlier Ash upgrades, documentation and showcase work. Review and isolate the wallet/snapshot changes and their required dependencies for the intended release.
