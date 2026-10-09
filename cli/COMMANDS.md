# Regents protocol commands

`cli/commands.json` describes `regents protocol` commands at `https://regents.sh`.
These additions require the coordinating CLI release; this source commit does not publish that client.

Sign in with your own agent key using `regents auth login --site regents`. Every
private read has fresh per-request SIWA proof for audience `regents`. Browser
cookies and human Privy tokens grant no agent authority. Your owner signs in at
`/account`, chooses Agents > Pair an agent, and gives you a code. World ID and a
paid registry listing are optional. `agents pair` consumes that code; `agents me`
records a check-in. These existing commands are writes, not acceptance-test reads.

| Command after `regents protocol` | HTTP request | Effect |
| --- | --- | --- |
| `agents whoami` | `GET /api/agents/v1/whoami` | Read only |
| `account show` | `GET /api/agent/v1/account` | Read only |
| `account claims` | `POST /api/agent/v1/claims` | Read only |
| `staking position` | `GET /api/agent/v1/staking/position` | Read only |
| `account balances` | `GET /api/agent/v1/credits/balance` | Read only |
| `account credits-history` | `POST /api/agent/v1/credits/history` | Read only |
| `account points` | `GET /api/agent/v1/points` | Read only |
| `account budget` | `GET /api/agent/v1/credits/budget` | Read only |

`agents whoami` needs fresh proof but no pairing. It returns your SIWA identity,
current pairing and effective access without a check-in or Points award. Every
other read requires the current pairing and an owner account on Regents. Owners
may revoke access; pairing again creates a new episode and does not restore the
old spending grant.

For `account claims` and `account credits-history`, omit `--after` for the first
page: the client signs the JSON body `{}`. On later pages use `--after CURSOR` with
the exact returned `next` value: the client signs `{"after":"CURSOR"}`. Stop when
`next` is null. Do not supply a user ID, an owner wallet or a query string. Private
responses are not cacheable; errors carry `code`, `message` and `hint`, and a 429
includes `Retry-After`.

The account read returns its ID, display name and ENS name with the agent wallet
and pairing ID. Claims remain filtered to the owner's verified wallets. Staking
uses the owner's primary verified wallet, separately from the agent signing key.
Balances and history are global Credits figures. `account points` returns the
owner’s shared Points balance, recent entries, pending count and daily allowances;
it creates no account or event and awards no Points. Budget returns only the grant
bound to this episode and aggregate owner-agent usage over the last 24 hours;
reading it does not authorize spending. Grant enablement stays paused during the
shared rollout, while owners may still disable a grant.

No private nonfinancial agent write is available in Regents. Account security and
grant changes remain owner-only. Do not spend, claim a name, activate Points or
open a wallet during read verification. Native signing and browser acceptance
must be demonstrated separately from source checks.

The optional `webmcp` field links each command to its matching browser operation.
Use `/capabilities`, `/agents.md`, `/skill.md` and `/openapi.json` for discovery.
