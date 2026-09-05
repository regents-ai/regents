# Agent wallets

Workspace policy: [WebMCP and CLI standard](../../../../control/docs/programs/webmcp-cli-standard.md)
(canonical Regent checkout).

Start with an existing wallet and explicit authority to use its funds. This works
for an agent acting for a human and for an autonomous agent with its own wallet.
Neither needs to import a key into Regent just to use an external payment client.

```sh
regents wallet setup
```

This command only shows choices. It does not read wallet configuration or keys,
create files or accounts, log in, contact a provider, or establish identity.
`--json` reports `selection_required` and `verification_state: not_checked`.

## Choose a path

| Choice | Command | What it does |
| --- | --- | --- |
| Existing Regent local signer | `regents wallet setup --provider local-key` | Prints local-signer guidance and prepare help; does not inspect configuration or keys. |
| Existing wallet, external client | `regents wallet setup --provider external` | Prints guidance; keeps keys with the existing signer. |
| Agentic Wallet CLI or MCP | `regents wallet setup --provider agentic-wallet` | Prints provider documentation and prerequisites; no login or installation. |
| Existing Coinbase CDP integration | `regents wallet setup --provider coinbase-cdp --wallet main` | Explicitly runs the existing account-selection/creation action and saves its state. Requires its provider setup. |

Local-key, external and Agentic Wallet guidance reports `guidance_only` and `not_checked`.
Selecting a provider does not connect it, prove control of an address, verify a
balance, or grant spending authority. `--wallet` requires the explicit
`coinbase-cdp` provider; it never silently chooses a provider.

Coinbase Agentic Wallet and the existing Coinbase CDP account integration are
different paths. Coinbase documents an Agentic Wallet CLI with email/OTP login,
and an Agentic Wallet MCP server with a companion wallet application. Choose one
through its own setup process. Regent does not run that process during discovery.
See the official [Agentic Wallet CLI guide](https://docs.cdp.coinbase.com/agentic-wallet/cli/welcome)
and [Agentic Wallet MCP guide](https://docs.cdp.coinbase.com/agentic-wallet/mcp/welcome).

The existing `regents wallet agentic status --json` command invokes the external
provider CLI and may start or download it. Read its reported status before
explicitly using login, verify or balance commands. Funding guidance alone does
not connect a wallet or confirm that money arrived. No live provider account or
payment was exercised when verifying this onboarding change.

## Give the signer bounded authority

For a human-delegated agent, the owner chooses the permitted recipient, asset,
network, amount and expiry. Enforce that delegation through signer or wallet
controls such as required owner approval, restricted session keys or provider
limits. Confirm which controls the chosen provider actually supports.

For an autonomous agent, fund a dedicated wallet with the amount intended for its
work. Keep reserves separately. A funded wallet and a selected provider do not
establish permission to spend on every request; the signer must enforce the
applicable authority.

Match the asset and network in the payment requirements before funding. Check
whether that signer or payment scheme requires gas. Do not infer compatibility
from a wallet brand or from a balance on another network.

Regent's local budgets help track and cap calls made through the budget-aware CLI
path. They are mutable local policy, not an independently enforced spending
boundary when the agent can edit them or call the signer through another client.
They do not restrict external clients. Fund limits and owner/signer controls
remain necessary for delegated authority.

## Local signer and Coinbase identity are separate

`regents wallet status` reports the existing Coinbase CDP account and its identity
readiness. It does not inspect the local key signer used by other Regent commands.
An address from one path is not proof that another path can sign for it.

The implemented local signer reads its configured private-key environment variable
or encrypted keystore. It is not a generic bridge to browser wallets, hardware
wallets or an external MCP server. `regents wallet import --stdin` remains an
explicit opt-in import into that encrypted keystore; discovery never imports or
requests a key. Only use it when the owner deliberately authorizes local key
custody, and supply the key securely through standard input, never a command-line
argument. Inspect the intended operation's signer requirements before using it.

Product sign-in and payment authorization are separate. A browser's cookies do not
authenticate a CLI command. A payment receipt does not grant access to an unrelated
private product operation. Use the authentication required by that operation.

## Pay through the CLI or an external client

First inspect the operation without paying. Inspection makes the specified HTTP
request, so use the correct method and body and understand whether an unprotected
endpoint executes the operation immediately:

```sh
regents x402 details --url <paid-url> --json
```

An external x402 client can use its existing signer; no Regent wallet import is
required. It must support the offered protocol version, scheme, network and asset,
and use `payment_required_response`, the complete original challenge including
all offers and extensions, for the same URL, method and request body. Keep the
original request authentication. The convenience `accepts` view and `x402 quote`
filter for the built-in signer's supported terms; they are not the complete external
client contract. Review the recipient and exact amount before authorizing payment.
The [official buyer guide](https://docs.x402.org/getting-started/quickstart-for-buyers)
describes the challenge, signed payment and result flow.

For local `x402 fetch`, `payment_status` (`settled`, `not_paid`, `not_required` or
`unknown`) is separate from HTTP `ok` and `status`. Keep `receipt_id`, `intent_id`
and the settlement result. An unknown attempt may have paid; its recovery receipt
and consumed intent prevent automatic replay.

For budget-aware `x402 pay`, retain `reservation_id` and
`provider_correlation_id` when returned. Unknown settlement or actual spend leaves
the reservation held; reconcile that attempt before authorizing another payment.

Retain the operation result and payment receipt together, including the network,
transaction or payment identifier and any settlement result. A successful tool or
provider process is not by itself evidence of settlement or delivery. An external
client's payment does not automatically create a Regent local budget entry or
receipt record. CLI and external clients must preserve the same operation inputs,
server errors and payment outcome; their authentication and local records can differ.

If a request times out or returns an unclear payment outcome, check the payment
identifier, settlement receipt and operation result before another paid attempt.
Do not assume the payment failed or retry blindly. Use the operation's documented
recovery or idempotency mechanism when available.
