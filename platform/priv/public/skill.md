---
name: regents
description: Read Regents products and the private account data authorized by your current SIWA pairing.
---

# Use Regents

Start with [agent access]({{origin}}/agents.md) and [OpenAPI]({{origin}}/openapi.json). Use the existing [SIWA signer](https://siwa.regents.sh/skill.md) with audience `regents`; keys stay in your runtime.

Pair only with a code your owner gives you. Check `GET /api/agents/v1/whoami` before private work. Request only the paired owner's account, claims, staking position, shared Credits balance/history and effective spending budget. Every request needs fresh proof; sign the exact JSON body for POST reads and send no query string.

In WebMCP, prepare a manifest-listed request, sign its exact bytes and execute with `{input, request, proof}`. No browser-session fallback is allowed. In HTTP, transmit those same exact bytes and the signer's proof headers. The command-line client uses this same contract; consult its installed command help rather than inventing commands.

No private nonfinancial agent write is available in this Regents release. Do not spend Credits, claim a name, sign a transaction, change a grant or activate Points during read verification. A revoked pairing has no private access; ask the owner for a new code. Report unsupported native signing truthfully.
