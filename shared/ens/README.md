# ens-elixir

[Changelog](CHANGELOG.md)
[Guide](USAGE.md)

`ens_elixir` is the Regent ENS and ERC-8004 identity helper package.

Use it when an Elixir app needs to read ENS state, verify that an ENS name
points at an agent, plan what is missing, or prepare the unsigned request that a
wallet should approve next.

The package reads, verifies, plans, and prepares. It does not hold private keys,
ask a wallet for approval, send chain transactions, or decide product
permissions.

## Installation

```elixir
def deps do
  [
    {:ens_elixir, path: Path.join(shared, "elixir-utils/ens")}
  ]
end
```

## When To Use It

Use `ens_elixir` for:

- ENSIP-25 proof checks
- ENS name reads and resolver inspection
- normalized ENS names, including DNS-imported names and other non-`.eth` names
- ENS text record, address, content hash, resolver, TTL, reverse name, and subname request preparation
- ERC-8004 registration reads and update planning
- wallet-ready request envelopes that can be handed to a browser wallet, Safe, CLI signer, or keyring
- Platform and Autolaunch trust-link flows that need clear “already set / ready / blocked” states

Use product code for:

- the approval screen
- transaction submission
- transaction confirmation
- product database writes after confirmation
- final permission or trust-label decisions

## Main Entry Points

| Function | Use it when |
| --- | --- |
| `AgentEns.read_name/1` | You need a name details page or CLI inspect output. |
| `AgentEns.verify/6` | You know the registry and agent id and only need to check an ENSIP-25 proof. |
| `AgentEns.verify_agent/5` | You want the built-in ERC-8004 network defaults. |
| `AgentEns.plan_link/1` | You need to explain what is already set and what is missing before asking for approval. |
| `AgentEns.prepare_bidirectional_link/1` | You want the next unsigned ENS, ERC-8004, and optional reverse-name requests. |
| `AgentEns.Tx` | You already know the exact ENS request to prepare. |
| `AgentEns.ERC8004.Registration` | You need to read or patch the JSON registration file referenced by an ERC-8004 agent. |
| `AgentEns.PrimaryName.verified_primary_identity/2` | You need a wallet's verified primary name and its picture. The picture is read only through the ENS avatar service, never from an address the avatar record names. |

## Common Flow

Most app flows should use this order:

1. Read the name with `AgentEns.read_name/1`.
2. Plan the identity link with `AgentEns.plan_link/1`.
3. Show the current state and the next action to the person or operator.
4. Prepare unsigned requests with `AgentEns.prepare_bidirectional_link/1`.
5. Send the prepared request to the app’s existing wallet or signer.
6. Confirm the transaction and update the product record that owns the workflow.

## Read A Name

```elixir
{:ok, details} =
  AgentEns.read_name(%{
    ens_name: "alice.eth",
    chain_id: 1,
    rpc_url: "https://eth.llamarpc.com",
    text_keys: ["avatar", "url", "description"]
  })
```

The result includes the normalized name, owner evidence, resolver address,
resolver capabilities, selected text records, ETH address, content hash, TTL,
wrapped-name evidence when available, and warnings for edge cases.

## Verify An ENSIP-25 Proof

```elixir
{:ok, status} =
  AgentEns.verify(
    "https://eth.llamarpc.com",
    "alice.eth",
    1,
    "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    42
  )

case status do
  :verified -> :ok
  :ens_record_missing -> {:error, :needs_ens_record}
end
```

Use `verify_agent/5` when the chain is one of the built-in ERC-8004 networks:

```elixir
AgentEns.verify_agent("https://eth.llamarpc.com", :ethereum_mainnet, 42, "alice.eth")
```

## Plan A Link

```elixir
{:ok, plan} =
  AgentEns.plan_link(%{
    ens_name: "alice.eth",
    chain_id: 1,
    registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    agent_id: 42,
    rpc_url: "https://eth.llamarpc.com",
    signer_address: "0x1111111111111111111111111111111111111111",
    reverse?: true
  })
```

The plan tells the caller whether:

- the ENS proof exists
- the ERC-8004 registration points back to the name
- the signer can change the ENS name
- the signer can change the agent registration
- a reverse name update is possible
- each next action is ready, already done, blocked, or skipped

## Prepare Wallet-Ready Requests

```elixir
{:ok, result} =
  AgentEns.prepare_bidirectional_link(%{
    ens_name: "alice.eth",
    chain_id: 1,
    registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    agent_id: 42,
    rpc_url: "https://eth.llamarpc.com",
    signer_address: "0x1111111111111111111111111111111111111111",
    reverse?: true
  })
```

Each prepared request is an `%AgentEns.TxRequest{}` with:

- `chain_id`
- `to`
- `value`
- `data`
- `expected_signer`
- `expires_at`
- `risk_copy`
- `idempotency_key`
- `description`

Hand that request to your wallet, Safe flow, keyring, or CLI signer. The package
does not submit it.

## Prepare One ENS Request

Use `AgentEns.Tx` for focused ENS work:

```elixir
{:ok, tx} =
  AgentEns.Tx.build_set_text_record_tx(%{
    ens_name: "alice.eth",
    chain_id: 1,
    resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
    key: "url",
    value: "https://example.com",
    signer_address: "0x1111111111111111111111111111111111111111"
  })
```

Other helpers prepare address, content hash, resolver, TTL, subname, and reverse
name updates.

## ERC-8004 Registration Files

`AgentEns.ERC8004.Registration` can fetch, parse, update, and serialize agent
registration files. Use it when the agent record itself should carry an ENS
service entry.

```elixir
{:ok, registration} =
  AgentEns.ERC8004.Registration.fetch(agent_uri)

{:ok, updated_registration} =
  AgentEns.ERC8004.Registration.upsert_ens_service(registration, "alice.eth")
```

If the flow needs a new registration URI, pass a publisher to
`prepare_erc8004_update/1`. The publisher owns storage and returns the new URI.

## Network Defaults

Built-in defaults are available for Ethereum mainnet and Ethereum Sepolia. Pass
explicit contract addresses for other networks.

## Return Shapes

Successful calls return `{:ok, value}`. Failures return
`{:error, %AgentEns.Error{}}`.

`%AgentEns.Error{}` carries:

- `kind`
- `message`
- `details`

Use `kind` for program behavior and `message` for operator-facing diagnostics.

## What This Package Does Not Do

- It does not manage private keys.
- It does not ask a wallet for approval.
- It does not submit transactions.
- It does not confirm transactions.
- It does not decide whether a product should show “verified.”
- It does not write Platform, Autolaunch, Techtree, or CLI state.

## Full Guide

For a longer guide with more examples, read [USAGE.md](USAGE.md).

## Development

```bash
mix deps.get
mix docs
```
