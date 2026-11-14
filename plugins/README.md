# Plugins

Regents reaches local agent runtimes through the `regents` command today, not
through packages in this directory. The directory exists so the product
monorepos share one layout (`platform/`, `plugins/`, `contracts/`). It holds no
plugin package yet.

## What exists today

Every runtime integration is owned, built, tested and released by
[regents-cli](https://github.com/regents-ai/regents-cli), the Python package
`regents-cli`:

```bash
uv tool install --python 3.14 'regents-cli[browser,mcp]'
uvx --from 'playwright==1.64.*' playwright install chromium
```

| Runtime | What the CLI does |
| --- | --- |
| Any agent with a shell | `regents protocol …` runs regents.sh's commands, as the [agent guide](https://regents.sh/agents.md) shows. |
| Claude Code, Codex and other MCP hosts | `regents browser --site regents` runs a local MCP server that opens regents.sh's pages in a hidden Chromium of its own and calls the tools each page offers, signing with this machine's agent key. |
| Claude Code, Codex and other MCP hosts | `regents mcp --site <site>` passes each message to a site's own MCP server at `/mcp`. regents.sh has no `/mcp` yet, so this is for the sites that do. |

In Claude Code, for example:

```bash
claude mcp add regents-pages -- regents browser --site regents
```

The [regents-cli README](https://github.com/regents-ai/regents-cli#readme) owns
the behavior of these commands. The CLI's tests cover them where they are, so
they stay in regents-cli rather than moving here.

## What would live here

A plugin package that a runtime installs on its own, without the `regents`
command generating it, belongs at `plugins/<runtime>/` with its own README,
manifest and checks. No such package exists, and this README is not a manifest.
