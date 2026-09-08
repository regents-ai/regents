# Regents Privy and wallet interaction checklist

Scope: `regents/platform`, preserving the current dirty checkout. Implement directly; no delegated agents, production deployment, signing, or credential-file reads.

## Acceptance checklist

- [ ] 1. Button intent: anonymous controls start sign-in; signed-in controls connect/select without a document reload.
- [ ] 2. Unified logout: explicit Disconnect and confirmed provider logout revoke server authority before one complete local wallet cleanup.
- [ ] 3. Same-origin tabs: logout clears wallet-dependent UI; the receiving tab verifies server state, without rebroadcast/delete loops.
- [ ] 4. Storage failures: logout still works without a handoff store; in-memory disconnection cannot be overwritten by SDK hydration.
- [ ] 5. Lifetime: stale login/connect/token callbacks, queued session work and disposed bridges cannot restore old state or start another mutation.
- [ ] 6. Readiness: passive hydration never treats missing tokens/wallets or an unavailable SDK as authoritative logout.
- [ ] 7. Feedback/retry: bounded startup, one auth modal/attempt, cancel/retry without stacked roots; explicit failures are visible and passive failures quiet.
- [ ] 8. Selection: only the explicit unambiguous connected Ethereum wallet is selected; signer/network checks remain enforced.
- [ ] 9. Private data: disconnect/switch clears the old wallet, cancels stale work and ignores late results; public readings remain.
- [ ] 10. Refresh/loading: cache-first public data, fresh current-wallet reads and component skeletons; no private data shared through protocol cache.
- [ ] 11. Transactions: each explicit action reaches the wallet; no automatic replay or fake cancellation of already-broadcast transactions.
- [ ] 12. Security: server verification/CSRF remain authoritative; cross-tab messages and hints carry no credentials.

## Audit findings before this implementation

The local branch already implements cache-first staking/overview rendering, skeletons, active-wallet login restoration, and connection-only page buttons. Remaining gaps: provider logout bypasses full wallet cleanup; disconnected state relies entirely on readable storage; sibling tabs do not consume disconnect notices; login completion only clears failed in-flight promises; SDK readiness/startup has no disposal handle; token callbacks can attempt passive completion outside readiness; late callbacks are not consistently bound to a provider lifetime; logout is refused when sessionStorage handoff cannot be written.

## Release boundary

### User testing checkpoint

Stopped editing at Sean's request so he can test locally. The changes remain in
`repos/regents/platform`, uncommitted and undeployed. No shared template was extracted.

Latest focused results: TypeScript passed; 346 wallet/auth JavaScript tests passed;
130 server tests passed; 24 selected authentication/browser checks passed. Logs:
`/tmp/regents-privy-unit-final.log`, `/tmp/regents-privy-server-final.log`, and
`/tmp/regents-privy-scope-browser.log`.

The broader site gate is not signed off: layout/theme integration failures belong
to the other session, per Sean's decision. The real Privy/Zerion canary remains open.
The Privy skill at `/Users/sean/.agents/skills/privy/SKILL.md` was loaded and the
`privy-docs` MCP was verified. Native SDK operations remain the integration boundary.

No server was listening on port 4002 at handoff. This agent's shell did not have
`PRIVY_APP_ID` or `PRIVY_VERIFICATION_KEY` exported, so a fake browser-test server was
not substituted for real sign-in. Use Sean's normal configured local launch setup.

A real Privy + Zerion canary on the approved deployed origin remains mandatory before production sign-off. Extension permission revocation is best-effort and cannot log the wallet out of unrelated applications. No claim of universal extension reliability is made.
