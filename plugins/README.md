# Plugins

Regents reaches local agent runtimes through the `regents` command today, not
through packages in this directory. The directory exists so the four product
monorepos share one layout (`platform/`, `cli/`, `plugins/`, `contracts/`). It
holds no plugin package yet.

## What exists today

Every runtime integration is owned, built, tested and released by
[cli/](../cli/README.md) as part of `@regentslabs/cli`:

| Runtime | What the CLI does | Source |
| --- | --- | --- |
| Hermes, OpenClaw | `regents plugin install` writes a typed tool bridge and its skills into the runtime's plugin directory under the user's home. | [plugin-bridge.ts](../cli/packages/regents-cli/src/internal-runtime/plugin-bridge.ts) |
| OpenClaw | Template and writer for the `regents-work` skill a local OpenClaw agent uses to run Regent work. | [agents/openclaw/](../cli/packages/regents-cli/src/agents/openclaw/) |
| Claude Code, Codex | `regents setup` registers the local `regents mcp serve` server. | [mcp/](../cli/packages/regents-cli/src/mcp/), [mcp-register.ts](../cli/packages/regents-cli/src/internal-runtime/mcp-register.ts) |
| Skills hosts | `regents setup skills` installs the agent skills bundled with the package. | [skills/](../cli/packages/regents-cli/skills/) |

The [CLI command contract](../cli/docs/shared-cli-contract.yaml) owns the
behavior of `regents plugin`, `regents setup` and `regents setup skills`. The
CLI's tests and workspace checks cover these files where they are, so they stay
in `cli/` rather than moving here.

## What would live here

A plugin package that a runtime installs on its own, without the `regents`
command generating it, belongs at `plugins/<runtime>/` with its own README,
manifest and checks. No such package exists, and this README is not a manifest.
