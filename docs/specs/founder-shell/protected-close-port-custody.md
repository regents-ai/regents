# Protected close-port custody

Read-only audits completed 2026-07-10 using explicit gpt-5.6-sol medium threads:

- Privy browser auth: `019f4c6b-a118-79a1-aa64-167d3aecc52b`
- Staking and redemption: `019f4c6b-9d9b-7cd1-b731-bffdf18c1a0e`

No files, Beads, environment files, production services, wallets, databases, or deployments were touched by either audit.

## Privy (`regent-2mf0.6`)

Preserve the verified browser-human boundary: CSRF plus a verified Privy access token creates or renews a signed local session holding only the canonical local human id. Verification precedes human lookup/create/update. Logout invalidates the session. Anonymous viewers remain anonymous. Posted provider ids, wallets, roles, and profile fields are never trusted.

Browser Privy humans and SIWA agents are distinct principal types and auth rails. Neither cookie nor Privy bearer may authenticate an agent route. Linked Privy wallets are profile evidence, not SIWA proof, onchain ownership truth, or signing authority.

The proposed canonical identity owner is one Ash HumanAccount resource with explicit verified-token register/refresh and self-read/avatar actions behind a boundary service. Use a System actor only after provider verification; human self actions are owner-only; anonymous and Agent actors are denied. Do not use a generic upsert that bypasses named action policies. Do not add a database session resource unless product requirements later require server revocation or multi-device management.

Do not copy literal salts, token-type ambiguity, mobile-specific wallet clearing, staking-specific error copy, raw provider logging, or non-encrypted profile data in the signed cookie. Required setting names may be documented, but secrets are never read from environment files or committed.

Audit proof: 29 Platform auth/browser tests, 29 browser Privy/wallet tests, 8 shared verifier tests, and 24 OpenAPI contract checks passed.

## Staking (`regent-2mf0.7`)

Preserve Base chain id 8453, deployed staking address from canonical configuration/manifest, token addresses read from the staking contract, public global reads, authenticated-wallet account reads, and user-signed prepared actions for stake, unstake, claim USDC, claim REGENT, and manual claim-and-restake. Automatic restaking is absent.

Named interfaces: `overview`, `account`, `prepare_stake`, `prepare_unstake`, `prepare_claim_usdc`, `prepare_claim_regent`, `prepare_claim_and_restake_regent`, `confirm_wallet_action`, and `refresh_position`. Prepared envelopes bind chain, contract target, zero native value, calldata, expected signer, expiry, deterministic action identity, and any required approval. Browser wallet switches chain, checks signer, performs approval if needed, signs/submits, requires a successful receipt, then reconciliation verifies and re-reads onchain truth.

Do not copy ignored expiry/idempotency/risk fields, discarded transaction hashes, the missing manual-restake manifest entry, or any assumption that submission equals success.

Audit proof: 63 focused staking/route tests, 113 Ash policy/controller/contract checks, 11 wallet/redeem browser tests, and 44 Foundry staking tests passed.

## Redemption (`regent-2mf0.8`)

The only admitted flow is Base NFT-to-REGENT redemption for Animata I and II: user-signed NFT operator approval, exact 80 USDC approval, redeem, and separate claim. Stripe-credit redemption and dormant future fields are absent.

Named interfaces: `status`, `eligible_collectibles`, `prepare_nft_approval`, `prepare_usdc_approval`, `prepare_redeem`, `prepare_claim`, and `confirm_wallet_action`. Canonical chain/address/ABI truth must enter the owning contract/chain manifest first. Each confirmation verifies expected chain, contract, signer, target, calldata, and a successful receipt before success UI, then re-reads onchain state.

Do not copy hardcoded/duplicated addresses and ABIs, unused constants, or the old bug that treated a reverted receipt as success. Chain-manifest coverage and meaningful receipt-status mutation tests are mandatory before equivalence can be claimed.
