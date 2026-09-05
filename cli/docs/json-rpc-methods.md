# JSON-RPC Methods

`regents-cli` uses JSON-RPC 2.0 over a Unix domain socket. Each request and response is one JSON line.

This file is generated from the current runtime method registry.

## Runtime

- `runtime.ping`
- `runtime.status`
- `runtime.shutdown`

## Agent

- `agent.init`
- `agent.status`
- `agent.profile.list`
- `agent.profile.show`
- `agent.harness.list`

## Doctor

- `doctor.run`
- `doctor.runScoped`
- `doctor.runFull`

## Auth

- `auth.siwa.login`
- `auth.siwa.logout`
- `auth.siwa.status`

## Techtree

- `techtree.forge.family.show`
- `techtree.forge.family.validate`
- `techtree.verify.run`
- `techtree.verify.status`
- `techtree.verify.receipt.show`
- `techtree.uplift.report`
- `techtree.notebooks.init`
- `techtree.notebooks.pair`

## X402

- `x402.details`
- `x402.quote`
- `x402.prepare`
- `x402.fetch`
- `x402.refund`
- `x402.receipts.get`

## Transports

- `gossipsub.status`

## Techtree Verify executor vocabulary

- `fixture`
- `hermes`
- `prime`
