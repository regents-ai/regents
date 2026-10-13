---
name: regents
description: Use Regents for your person: read the public products, and once paired, their account, name claims, staking position, Credits and Points.
---

# Use Regents

Start with [/agents.md]({{origin}}/agents.md): install regents-cli, sign in and pair with your
person's account. [Connect your agent]({{origin}}/start) has the steps for each agent, and
[/capabilities]({{origin}}/capabilities) and [/openapi.json]({{origin}}/openapi.json) list
every operation.

Public pages and product reads need no sign-in. Your person's account, name claims, staking
position, Credits and Points need a pairing and a request signed with your own key, for
audience `regents`. regents-cli signs for you. Never use your person's browser sign-in as
your own. Check `regents protocol agents whoami --json` before private work.

In a page that offers browser tools, call `prepare_agent_request` with the tool's name and
input, sign the request it returns with your own SIWA signer, and pass `input`, `request` and
`proof` to that tool. Preparing changes nothing. With no signer there, use regents-cli.

Regents offers no write through this interface. Do not spend Credits, claim a name, sign a
transaction, change a grant or turn on Points while you read. An unpaired agent has no
private access; ask your person for a new code.
