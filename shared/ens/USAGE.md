# Using ens-elixir

This guide shows `ens_elixir` as a set of jobs a product app or CLI command can
perform.

The package exists to keep ENS and ERC-8004 identity work in one place:
normalize names, read chain state, verify proof records, plan missing work, and
prepare unsigned requests. The host app owns wallet approval, transaction
submission, confirmation, and product records.

Do not limit callers to `.eth` names. Normalize the submitted name, then resolve
it. DNS-imported names and other dotted ENS names should use the same path.

## Pick The Right Starting Point

| Job | Start with |
| --- | --- |
| Show the current state of a name | `AgentEns.read_name/1` |
| Check whether an ENSIP-25 proof exists | `AgentEns.verify/6` |
| Check a built-in ERC-8004 network | `AgentEns.verify_agent/5` |
| Decide what is missing before approval | `AgentEns.plan_link/1` |
| Prepare the next identity-link requests | `AgentEns.prepare_bidirectional_link/1` |
| Prepare one exact ENS request | `AgentEns.Tx` |
| Patch an ERC-8004 registration file | `AgentEns.ERC8004.Registration` |

## The Main Inputs

Most flows use this input shape:

```elixir
%{
  ens_name: "alice.eth",
  chain_id: 1,
  rpc_url: "https://eth.llamarpc.com",
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  signer_address: "0x1111111111111111111111111111111111111111"
}
```

Optional fields include:

- `text_keys`: selected text records to read
- `resolver_address`: resolver to use for a prepared write
- `reverse?`: whether to include reverse-name planning
- `publisher`: a module or function that stores updated ERC-8004 registration content and returns a URI
- explicit ENS registry, name wrapper, reverse registrar, and ERC-8004 registry addresses when not using a built-in network

## Read A Name

Use `AgentEns.read_name/1` for inspect pages, CLI detail commands, and review
screens.

```elixir
{:ok, details} =
  AgentEns.read_name(%{
    ens_name: "alice.eth",
    chain_id: 1,
    rpc_url: "https://eth.llamarpc.com",
    text_keys: ["avatar", "url", "description"]
  })
```

The result can include:

- normalized ENS name
- registry owner
- wrapped owner when available
- resolver address
- resolver capability hints
- ETH address
- content hash
- TTL
- requested text records
- warnings about missing or unsupported records

Read results are evidence snapshots. Product apps should store their own
workflow state and refresh chain evidence when it matters.

## Verify A Proof

Use `AgentEns.verify/6` when you already know the chain, registry, agent id, and
ENS name:

```elixir
{:ok, status} =
  AgentEns.verify(
    "https://eth.llamarpc.com",
    "alice.eth",
    1,
    "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    42
  )
```

Possible success statuses are:

- `:verified`
- `:ens_record_missing`

Use `AgentEns.Verify.verified?/1` when you want a boolean from that status:

```elixir
{:ok, status} = AgentEns.verify(rpc_url, name, chain_id, registry, agent_id)
AgentEns.Verify.verified?(status)
```

Use `verify_agent/5` for a built-in ERC-8004 network:

```elixir
AgentEns.verify_agent(
  "https://eth.llamarpc.com",
  :ethereum_mainnet,
  42,
  "alice.eth"
)
```

## Plan Before Asking For Approval

Use `AgentEns.plan_link/1` before showing any approval step.

```elixir
{:ok, plan} =
  AgentEns.plan_link(%{
    ens_name: "alice.eth",
    chain_id: 1,
    rpc_url: "https://eth.llamarpc.com",
    registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    agent_id: 42,
    signer_address: "0x1111111111111111111111111111111111111111",
    reverse?: true
  })
```

The plan helps answer:

- Does the ENS name already contain the right ENSIP-25 text record?
- Does the ERC-8004 agent registration already point back to the ENS name?
- Can the signer update the ENS name?
- Can the signer update the agent registration?
- Should a reverse-name request be prepared?
- Which actions are `:ready`, `:noop`, `:blocked`, or `:skipped`?

Use the plan to explain the next step. Do not ask a wallet to approve a request
until the plan says that request is ready.

## Prepare A Full Link

Use `AgentEns.prepare_bidirectional_link/1` when you want the next unsigned
requests for a two-sided identity link.

```elixir
{:ok, result} =
  AgentEns.prepare_bidirectional_link(%{
    ens_name: "alice.eth",
    chain_id: 1,
    rpc_url: "https://eth.llamarpc.com",
    registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    agent_id: 42,
    signer_address: "0x1111111111111111111111111111111111111111",
    reverse?: true
  })
```

The result includes:

- `:plan`: the read-only plan
- `:ensip25`: the ENS proof request, `:noop`, or `:blocked`
- `:erc8004`: the agent registration request, `:noop`, or `:blocked`
- `:reverse`: the reverse-name request, `:noop`, `:blocked`, or `:skipped`

## Prepare One Request

Use `AgentEns.Tx` when the product already knows the exact ENS change it wants.

Set a text record:

```elixir
AgentEns.Tx.build_set_text_record_tx(%{
  ens_name: "alice.eth",
  chain_id: 1,
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  key: "url",
  value: "https://example.com",
  signer_address: "0x1111111111111111111111111111111111111111"
})
```

Set an ETH address:

```elixir
AgentEns.Tx.build_set_addr_tx(%{
  ens_name: "alice.eth",
  chain_id: 1,
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  address: "0x2222222222222222222222222222222222222222",
  signer_address: "0x1111111111111111111111111111111111111111"
})
```

Create or update a subname:

```elixir
AgentEns.Tx.build_create_subname_tx(%{
  parent_name: "alice.eth",
  chain_id: 1,
  label: "agent",
  owner_address: "0x2222222222222222222222222222222222222222",
  resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
  ttl: 0,
  signer_address: "0x1111111111111111111111111111111111111111"
})
```

Set the primary name:

```elixir
AgentEns.Tx.build_reverse_set_name_tx(%{
  chain_id: 1,
  ens_name: "alice.eth",
  signer_address: "0x1111111111111111111111111111111111111111"
})
```

## Wallet-Ready Request Shape

Prepared changes return `%AgentEns.TxRequest{}`:

```elixir
%AgentEns.TxRequest{
  chain_id: 1,
  to: "0x...",
  value: "0x0",
  data: "0x...",
  expected_signer: "0x1111111111111111111111111111111111111111",
  expires_at: "2026-05-06T12:00:00Z",
  risk_copy: "Sets an ENS text record.",
  idempotency_key: "...",
  description: "Set ENS text record"
}
```

The host app should:

1. Check `expected_signer`.
2. Show `risk_copy` or product-specific review copy.
3. Send `to`, `value`, `data`, and `chain_id` to the wallet or signer.
4. Confirm the transaction.
5. Update product state after confirmation.

## ERC-8004 Registration Files

Use `AgentEns.ERC8004.Registration` when an agent registration file needs an ENS
service entry.

```elixir
{:ok, registration} =
  AgentEns.ERC8004.Registration.fetch(agent_uri)

{:ok, next_registration} =
  AgentEns.ERC8004.Registration.upsert_ens_service(registration, "alice.eth")

{:ok, json} =
  AgentEns.ERC8004.Registration.serialize_registration(next_registration)
```

To prepare an ERC-8004 update, the package needs a publisher that stores the
new registration content and returns the new URI:

```elixir
publisher = fn body ->
  MyApp.RegistrationStorage.put(body)
end

AgentEns.prepare_erc8004_update(%{
  ens_name: "alice.eth",
  chain_id: 1,
  rpc_url: "https://eth.llamarpc.com",
  registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  agent_id: 42,
  signer_address: "0x1111111111111111111111111111111111111111",
  publisher: publisher
})
```

## Network Defaults

`AgentEns.Networks` includes defaults for:

- `:ethereum_mainnet`
- `:ethereum_sepolia`

Use explicit addresses for other networks.

```elixir
{:ok, defaults} = AgentEns.Networks.get(1)
```

## Regent-Specific Prepared Actions

The top-level `AgentEns` module also includes Regent helper entry points for
flows that prepare wallet-ready Regent identity actions:

- `prepare_regent_subname_upgrade/1`
- `prepare_regent_ensip25_update/1`
- `prepare_regent_addr_update/1`

Use these from Regent product code when the product has already decided which
Regent identity action it needs.

## What To Show In A Product

Show product-safe state:

- “This name is connected.”
- “This name needs one wallet approval.”
- “This wallet cannot update this name.”
- “This agent record needs to point back to the name.”
- “The request is ready for approval.”

Avoid showing raw module names, request ids, calldata, resolver internals, or
registry internals in customer-facing UI. Keep those details in operator logs or
developer screens.

## Module Map

- `AgentEns`: top-level API for most callers
- `AgentEns.Verify`: ENSIP-25 verification
- `AgentEns.Read`: ENS name inspection
- `AgentEns.Plan`: link planning
- `AgentEns.Link`: prepared link requests
- `AgentEns.Tx`: focused ENS, reverse, and subname request builders
- `AgentEns.TxRequest`: wallet-ready request envelope
- `AgentEns.RecordKey`: ENSIP-25 text record keys
- `AgentEns.ERC7930`: interoperable registry address encoding
- `AgentEns.ERC8004.Registration`: registration-file read and patch helpers
- `AgentEns.Networks`: built-in network defaults
- `AgentEns.Normalize`: ENS name normalization helpers

## Final Advice

Use `AgentEns.plan_link/1` before approval. It gives the caller the clearest
view of what is already true, what is missing, and whether the next request is
ready.
