# Implementation Phases

## Local foundation

- workspace, config, paths, and shared types
- JSON-RPC server and client over the local Unix socket
- local runtime, agent profiles, doctor checks, and gossipsub status

## Authentication and payments

- SIWA nonce, message, verification, and session persistence
- identity and signed-request envelopes
- wallet, budget, receipt, and x402 boundaries

## Product contracts

- repository-owned shared-services contract and binding
- reviewed Platform and Autolaunch contract copies and bindings
- reviewed canonical Ash Techtree contract copy and binding

## Shipped Techtree surface

- local paper and freeform notebook initialization
- local notebook pairing

Any future API-backed Techtree command starts with a reviewed canonical contract-copy change.
