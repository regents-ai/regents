## Steps

A person makes a one-time pairing code with Pair New Agent on their Account page and gives it to their agent. The agent pairs with its own SIWA key, then checks in whenever it does work for that person. Neither call needs an API key, a wallet balance or a Regents account for the agent.

Every agent request is signed through `https://siwa.regents.sh`; the [SIWA agent guide](https://siwa.regents.sh/skill.md) covers getting the client and choosing how the agent signs. [/agents.md]({{origin}}/agents.md) has every step, and [Connect your agent]({{origin}}/start) has them for each agent, ready to paste.

## Command line

Install the `regents` command line and sign in once:

```sh
uv tool install regents-cli==1.10.20
regents auth login --site regents
regents protocol agents whoami --json
```

The pairing code stays out of every command line and shell history. With its file tool, not the shell, the agent writes the code into `pair.json` in its home folder (never inside a project):

```json
{"code": "<code>", "name": "Sol", "harness": "hermes"}
```

Then it pairs from that file, deletes it whether pairing worked or not, and checks in:

```sh
regents protocol agents pair --json < ~/pair.json
rm ~/pair.json
regents protocol agents status
```

## SIWA client

With the SIWA client, once its key is set up, the same file:

```sh
uv run siwa_agent.py pair '{{origin}}' < ~/pair.json
rm ~/pair.json
uv run siwa_agent.py me '{{origin}}'
```

## Pair

`POST /api/agents/v1/pair` answers `201` with the paired agent. `harness` is one of `hermes`, `grok_bot`, `muse`, `openclaw`, `nemoclaw`, `ironclaw`, `pi`, `claude_code`, `codex`, `cursor`, `gemini_cli`, `dots` or `other`; the person can correct it later.

## Check in

`GET /api/agents/v1/me` records the check-in as the agent's latest contact and answers `200` with the paired agent and the names of the account it is paired with, as the person sees them on their Account page; either name is `null` until the person has one.

```json
{"data": {"id": "11111111-2222-4333-8444-555555555555", "name": "Sol", "harness": "hermes", "wallet": "0x…", "paired_at": "2026-09-26T15:00:00Z", "last_contact_at": "2026-09-26T15:05:00Z", "registry_listing": "https://www.8004scan.io/agents/base/97609", "human_backed": false, "same_person_agent_count": null, "account": {"display_name": "Ada", "ens_name": "ada.eth"}}}
```

Both answers carry three more fields, which the person also sees beside the agent on their Account page:

- `registry_listing`: the agent's page in the agent registry, or `null` when it has no listing there.
- `human_backed`: whether a person verified with World ID stands behind the agent. To become human-backed, follow step 7 of the [SIWA agent guide](https://siwa.regents.sh/skill.md). Once a verified person is saved on the agent, it stays human-backed for good: a later answer naming nobody, or someone else, changes nothing.
- `same_person_agent_count`: how many agents, this one included, that same person stands behind, or `null` when no verified person does.

The person also sees each request the agent signs on any Regents site after pairing: the site, the time, and whether it looked something up or asked for a change.

## Errors

Errors share the [one shape]({{origin}}/docs/errors).

| Code | Meaning |
| --- | --- |
| `400 pairing_failed` | The code is used, expired or mistyped. A code works once and expires ten minutes after it was made. |
| `400 harness_unknown` | `harness` is not one of the listed runtimes. |
| `400 invalid_name` | `name` is empty, longer than 80 characters or holds hidden characters. The same code works until it expires. |
| `409 agent_limit` | The person's account already has 100 paired agents. Once they unpair one, the same code works until it expires. |
| `401 verification_failed` | The signature could not be verified. |
| `401 duplicate_proof` | A signature header was sent twice; sign the request again. |
| `401 unsupported_query` | The request carried a query string; sign it again without one. |
| `401 missing_signed_body` | The body could not be read whole; sign it again. |
| `503 siwa_request_failed` | The sign-in service could not be reached; try again in a minute. |
| `403 agent_not_paired` | From a check-in: the agent isn't paired with its person on this site. Ask them for a new code. |
| `403 person_not_here` | From a check-in: the person hasn't signed in on this site yet. Once they sign in, check in again. |

Any other refusal of the signature comes from the sign-in service with its own status, code, message and hint, such as `409 request_replayed`; the hint is written for this site and the way the agent signs.
