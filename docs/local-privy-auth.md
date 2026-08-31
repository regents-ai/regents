# Local Privy sign-in

This flow uses only a loopback PostgreSQL database named `ash_platform_dev`. Database startup stays off unless explicitly enabled.

```sh
createdb ash_platform_dev
cp .env.example .env
touch .env.local
printf '%s\n' 'source_env .env' 'source_env_if_exists .env.local' > .envrc
```

Put the real local values in the ignored `.env.local`:

```dotenv
export PRIVY_APP_ID='YOUR_PRIVY_APP_ID'
export PRIVY_VERIFICATION_KEY='-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----'
export X_OAUTH_CLIENT_ID='YOUR_X_OAUTH_CLIENT_ID'
```

`PRIVY_VERIFICATION_KEY` is Privy's PEM-encoded ES256 verification public key, not the Privy app
secret. Native multiline PEM and one-line `\n`-escaped values are both accepted.

## Before the first sign in

Turn identity tokens on for this app in the Privy Dashboard, under the app's user-data settings.
Signing in sends two things Privy issues for the same session: proof of the session itself, and the
separately signed record of the accounts connected to it. Regent checks both and accepts neither
alone, so with identity tokens switched off every sign-in attempt is refused.

`X_OAUTH_CLIENT_ID` is optional. When present, register this exact OAuth callback in the X app:

```text
http://localhost:4000/auth/x/callback
```

The X app must support Authorization Code with PKCE as a public client. Regent requests only
`tweet.read users.read`, does not request offline access, and does not need or store an X client
secret or provider token. Without the client ID, the Profile X and Company X controls remain visible
but disabled with an explanatory message.

Review the files, then load them and start the app:

```sh
direnv allow
mix ash_platform.setup_local_auth
mix phx.server
```

Open `http://localhost:4000/app` and use **Sign In**. `localhost` is the address to use; there is no separate setup for any other spelling of it. Sign out from the account control to verify both the local session and Privy session are cleared.

The setup task refuses production mode, non-loopback database hosts, and database names that do not end in `_dev` or `_test`. It prepares the protected local `platform.platform_human_users` fixture and applies the current Ash Platform schema only to that guarded local database. It is not a production setup path.

## Current dependency risk

`npm audit --omit=dev --audit-level=high` reports no high-severity findings. The app overrides transitive WebSocket 8.x copies to fixed release 8.21.0 while retaining Privy React 3.34.0. Ten moderate `uuid` findings remain beneath Privy’s MetaMask/Wagmi dependency path. npm’s forced suggestion downgrades Privy and is not an acceptable fix; do not run `npm audit fix --force`. Recheck when Privy publishes a compatible dependency update.
