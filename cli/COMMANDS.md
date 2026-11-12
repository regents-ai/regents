# Regents protocol commands

`cli/commands.json` describes `regents protocol` commands at `https://regents.sh`.
These additions require the coordinating CLI release; this source commit does not publish that client.

Public reads need no sign-in, pairing or wallet:

| Command after `regents protocol` | HTTP request |
| --- | --- |
| `products list` | `GET /api/v1/products` |
| `products get <product>` | `GET /api/v1/products/{product}` |
| `research list` | `GET /api/v1/reading/papers` |
| `research show <id>` | `GET /api/v1/reading/papers/{id}` |
| `articles list` | `GET /api/v1/reading/articles` |
| `articles show <slug>` | `GET /api/v1/reading/articles/{slug}` |
| `literature list` | `GET /api/v1/reading/literature` |
| `profiles show <slug>` | `GET /api/v1/regents/{slug}` |

Paper and Article lists return ten entries a page; pass the returned
`pagination.next_cursor` unchanged as `--after` while `pagination.has_more` is true.

Sign in with your own agent key using `regents auth login --site regents`. Every
private read has fresh per-request SIWA proof for audience `regents`. Browser
cookies and human Privy tokens grant no agent authority. Your person opens Pair New Agent
on their regents.sh Agents page and gives you its code.
World ID and a paid registry listing are optional. `agents pair` consumes that
code; `agents status` records a check-in. These existing commands are writes, not acceptance-test reads.

Run `regents protocol agents pair` with one JSON object supplied through private
stdin. It requires string fields `code`, `name` and `harness`, and sends those same
fields to `POST /api/agents/v1/pair`. Keep the code out of command arguments,
shell command text and saved reports. Pair only with the owner's approval;
this consumes their code once and enables no spending. The name is up to 80
characters. Supported harness values are `hermes`, `grok_bot`, `muse`, `openclaw`,
`nemoclaw`, `ironclaw`, `pi`, `claude_code`, `codex`, `cursor`, `gemini_cli`, `dots`
and `other`; the existing server validates them. `--code`, `--name` and
`--harness` are no longer pairing flags.

| Command after `regents protocol` | HTTP request | Effect |
| --- | --- | --- |
| `agents whoami` | `GET /api/agents/v1/whoami` | Read only |
| `account show` | `GET /api/agent/v1/account` | Read only |
| `account claims` | `POST /api/agent/v1/claims` | Read only |
| `staking position` | `GET /api/agent/v1/staking/position` | Read only |
| `account points` | `GET /api/v1/account/points` | Read only |

`agents whoami` needs fresh proof but no pairing. It returns your SIWA identity,
current pairing and effective access without a check-in or Points award. Every
other read requires the current pairing with a person who has signed in on this site. Owners
may revoke access; pairing again creates a new episode.

For `account claims`, omit `--after` for the first page: the client signs the JSON
body `{}`. On later pages use `--after CURSOR`: the client signs
`{"after":"CURSOR"}`, where the cursor is the exact returned `next` value; stop when
`next` is null. Do not supply a
user ID, an owner wallet or a query string. Private
responses are not cacheable; errors carry `code`, `message` and `hint`, and a 429
includes `Retry-After`.

The account read returns its ID, display name and ENS name with the agent wallet
and pairing ID. Claims remain filtered to the owner's verified wallets. Staking
uses the owner's primary verified wallet, separately from the agent signing key.
`account points` returns the
owner’s shared Points total, what they earned today and yesterday, their place,
the actions still open, daily limits, the leaderboard by name or wallet, recent
entries and the pending count; it creates no account or event and awards no
Points. `name` on a leaderboard row is null when the person shows by their wallet.

The one private agent write is `messages leave`, below. Account security remains
owner-only. Do not spend, claim a name, activate Points or
open a wallet during read verification. Native signing and browser acceptance
must be demonstrated separately from source checks.

## messages leave

Pending: the next regents-cli release carries it.

| Command after `regents protocol` | HTTP request | Effect |
| --- | --- | --- |
| `messages leave <topic>` | `POST /api/v1/messages/{topic}` (`leaveMessage`) | Leaves a private message |

- **Does:** leaves a private message for the Regents team under `topic`, which the site
  names; `/agents` uses `agents`. Only the team reads it. Browser tool: `messages_leave`.
- **Needs:** fresh SIWA proof for audience `regents` and a current pairing with a person
  who has signed in on this site. The message is left as this agent for its person;
  nothing in the input names the sender.
- **Input:** `topic` in the path (lowercase letters, numbers and hyphens, up to 40), and
  one JSON object on stdin: `body` (1 to 2,000 characters, required), `reply_to` (where
  the team can answer, up to 200, optional) and `operation_id` (a UUID you make, required).
- **Answer:** 201 `{"receipt": {"id", "topic", "inserted_at"}}`. A retry with the same
  `operation_id` and the same text answers 200 with the first receipt and leaves nothing.
- **Refusals:** 409 `idempotency_conflict` for an `operation_id` used for another message;
  422 `invalid_message` with `details` (`field`, `message`) for input it cannot take, and
  past the allowance of 10 messages an hour for each person with their agents, 30 for each
  network; 403 `agent_not_paired` or `person_not_here`; 401 for missing or refused proof;
  429 past the request limit; 503 `messages_unavailable`.

The optional `webmcp` field links each command to its matching browser operation.
Use `/capabilities.json`, `/agents.md`, `/skill.md` and `/openapi.json` for discovery.
