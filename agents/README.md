# Regent Agents

One pairing between a person and their agent, shared by every Regent site.

A person makes a pairing code on their regents.sh Account page and gives it to
their agent. The agent pairs on any Regent site, signing the request with its
SIWA key, and afterwards every site's check-in answers with that same pairing.
The agent's side is described in the sign-in guide at
https://siwa.regents.sh/skill.md.

- `POST /api/agents/v1/pair` with `{code, name, harness}` answers `201 {data: agent}`.
- `GET /api/agents/v1/me` answers `200 {data: agent + account}`.
- Both answers carry `registry_listing`: the agent's page in the agent registry,
  as the SIWA service names it, or null when the agent has no listing; and
  `human_backed`: whether a person verified with World ID stands behind it.
- A refusal is `{error: {code, message, hint}}`: `pairing_failed` (400),
  `harness_unknown` (400, the hint lists the accepted names), `not_paired` (404),
  `verification_failed` (401), `verification_unavailable` (503), or the SIWA
  service's own refusal, passed on unchanged: its status, code, message and a
  hint written for the site and the agent's signing tool.

The person is named by their Privy user ID and the agent by its key's address.
One key belongs to one person. A code works once, for ten minutes; a person has
one live code and can make a new one once a minute. Pairing only says whose
agent this is: what a paired agent may do on a site stays that site's decision.

## Adopting it on a site

Depend on it the way the site depends on `regent_identity`:

```elixir
{:regent_agents, git: @regents, ref: @regents_ref, sparse: "agents"}
```

Configure it with the site's repository, PubSub, SIWA audience, and how a
check-in names the person's account (a function taking the Privy user ID and
returning a JSON-ready map):

```elixir
config :regent_agents,
  repo: MySite.Repo,
  pubsub: MySite.PubSub,
  account: {MySite.Agents, :account},
  siwa: [url: "https://siwa.regents.sh", audience: "mysite"]
```

Mount the two requests behind the site's own rate limit (Regents allows 10
pair requests and 60 check-ins a minute from one address). Mount them outside
any agent sign-in pipeline: the package checks the signature itself, and a
second check would spend the signed request, so the agent would be told
`request_replayed`. The endpoint's body reader must keep the raw body in
`conn.assigns.raw_body`, because the agent signs the exact bytes:

```elixir
forward "/api/agents/v1", RegentAgents.HTTP
```

Start the listener in the application's children, after the repository and
PubSub:

```elixir
RegentAgents.Listener
```

It opens one connection of its own with the repository's settings and listens
for the changes every site announces through the shared database. That needs
a direct connection: a pooler that hands out connections per transaction
drops the listening.

A page acting for a signed-in person passes
`%RegentAgents.Person{privy_user_id: ...}`, built only from the site's own
verified session, to `issue_pairing_code`, `list_my_agents`, `get_my_agent`,
`change_agent_harness` and `unpair_agent`, and subscribes to
`RegentAgents.topic(privy_user_id)` to hear `:agents_changed` whenever that
person's agents are paired, check in, are corrected or are unpaired on any
Regent site.

## Migrations

Regents alone runs `RegentAgents.Migrator.up(Regents.Repo)` in its release step.
It creates the `regent_agents` schema with its own migration ledger. Other sites
never run it.

## Checks

`make check-agents` from the repository root, with `MIX_TEST_PARTITION` set.
