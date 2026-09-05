# Regents CLI Test Matrix

The required repository gate is:

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
pnpm build
pnpm typecheck
pnpm test
```

## Contract coverage

- the shared CLI contract matches the generated command metadata
- the JSON-RPC YAML and generated Markdown match the live runtime registry
- the checked-in shared-services and Ash Techtree contract copies match their generated bindings
- every shipped contract command has a route

## Local runtime coverage

- runtime start, status, ping, and shutdown
- agent initialization, profile reads, and harness listing
- scoped runtime, auth, and transport doctor checks
- SIWA session and signed-envelope construction
- notebook `init` and `pair` through the real local daemon
- x402 runtime method dispatch

## Product and safety coverage

- Platform, Autolaunch, Agentbook, staking, wallet, and x402 command groups retain their focused suites
- protected writes retain their existing signer and authority tests
- deleted old-tree commands return `unknown_command`
- generated command lists, help, MCP tools, and packaged skills expose no retired Techtree command
