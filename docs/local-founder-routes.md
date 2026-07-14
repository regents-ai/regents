# Test Privy, Stake, and Redeem locally

This is the single local handoff for the first protected `ash-platform` routes. It keeps the
automated proof separate from actions that would create real Base mainnet transactions.

## 1. Install and verify

From a terminal:

```sh
cd /Users/sean/Documents/regent/ash-platform
mix deps.get
npm install
mix precommit
npm run typecheck
npm test
npm run test:budgets
npm run test:browser
```

The browser suite uses deterministic in-memory wallets. It does not contact a real wallet or send
a transaction.

## 2. Prepare the local login database

Create the local database once. Skip this command if it already exists:

```sh
createdb ash_platform_dev
```

Create the ignored direnv files from the tracked example:

```sh
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
```

Put only the real local values in `.env.local`, using the same export format:

```dotenv
export PRIVY_APP_ID='YOUR_PRIVY_APP_ID'
export PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----'
```

`PRIVY_VERIFICATION_KEY` is the PEM-encoded ES256 verification **public key** for the Privy app,
not the Privy app secret. Both a native multiline PEM and a secret-manager-safe value containing
literal `\n` escapes are accepted, matching the verified old-platform behavior.

Allow direnv after reviewing the files:

```sh
direnv allow
```

Create only the local Human Account table and start Phoenix:

```sh
mix ash_platform.setup_local_auth
mix phx.server
```

The setup command refuses production mode, non-loopback database hosts, and database names that do
not end in `_dev` or `_test`.

## 3. Verify real Privy sign-in without moving value

Open [http://localhost:4000/app](http://localhost:4000/app).

1. Choose **Sign In** and connect the Privy wallet you intend to inspect.
2. Confirm the upper-right account control changes from **Sign In** to the signed-in identity.
3. Open [http://localhost:4000/stake](http://localhost:4000/stake). Confirm the page shows Base,
   the verified staking contract, and that wallet's REGENT position and rewards.
4. Open [http://localhost:4000/redeem](http://localhost:4000/redeem). Confirm the page shows the
   verified 80 USDC price, 5,000,000 REGENT payout, seven-day vest, and that wallet's balance,
   allowance, and vest status.
5. Use **Sign Out**, then confirm the account control returns to **Sign In** and protected action
   controls are unavailable.

Everything in this section is read-only. Reviewing an action is also safe until you choose
**Confirm in wallet** and approve the wallet prompt.

## 4. Optional real staking check

`/stake` uses the deployed Base mainnet contracts. If you decide to continue past the review, the
wallet prompt is a real transaction and uses real REGENT and ETH for gas.

Recommended first check:

1. Enter a deliberately small REGENT amount.
2. Choose **Review stake** and inspect the wallet, amount, contract, network, and `0 ETH` native
   value shown by the app.
3. Stop here if you only wanted to test preparation. No transaction has been sent.
4. If you intentionally choose **Confirm in wallet**, a stake can require two separate prompts:
   an exact REGENT approval, followed only after server verification by the stake transaction.

The other supported actions are unstake, claim USDC, claim REGENT, and manual claim-and-restake.
There is no automatic restaking or server signing.

## 5. Optional real Animata redemption check

`/redeem` also uses Base mainnet. Merely testing the page should stop before wallet confirmation.
An actual redemption consumes the selected Animata NFT, requires exactly 80 USDC, and starts the
real REGENT vest. Do not complete it unless that is your intended onchain action.

The four steps are intentionally independent:

1. NFT collection approval — a collection-wide approval that remains until revoked.
2. Exact 80 USDC approval.
3. Redeem the selected Animata I or II token.
4. Claim REGENT that is currently unlocked.

Each step has its own review and wallet prompt. The app never chains the next step automatically.
After submission, **Retry verification** checks the existing hash; it never sends another
transaction.

## Known dependency status

All locked Elixir packages are current. The JavaScript packages are current on their compatible
lines. `@solana/kit` remains at `6.10.0` because the current latest Solana system/token packages
used by Privy require Kit 6; installing Kit 7 would create an incompatible peer set.

The app pins transitive WebSocket 8.x copies to fixed release 8.21.0, so the current high-severity
npm audit is clear. Ten moderate `uuid` advisories remain beneath Privy’s MetaMask/Wagmi path.
npm’s forced suggestion would downgrade Privy and is not an acceptable fix. Do not run
`npm audit fix --force`; recheck when Privy ships a compatible dependency update.
