# Manual Acceptance

Use this flow to verify the local Techtree notebook survivor after the canonical contract cutover.

## Preconditions

- dependencies are already installed
- the six repository checks are green
- no external service is required

## Local notebook flow

Start the local runtime:

```bash
pnpm --filter @regentslabs/cli exec regents run
```

In another terminal, create a temporary paper notebook:

```bash
pnpm --filter @regentslabs/cli exec regents techtree notebooks init \
  --kind paper \
  --title "Cutover acceptance" \
  --source "local acceptance" \
  --workspace-path /tmp/regents-cutover-notebook \
  --json
```

Confirm that the result names `notebook.json`, `analysis.py`, and the next pair command. Then pair it:

```bash
pnpm --filter @regentslabs/cli exec regents techtree notebooks pair \
  --workspace-path /tmp/regents-cutover-notebook \
  --json
```

Confirm that the result points to the same workspace and returns only the local marimo edit step. No publish, search, chat, benchmark, science, or work-feed command should appear.

## Contract and command proof

```bash
pnpm check:workspace
pnpm check:openapi
pnpm check:cli-contract
```

The workspace report must list the Ash Techtree contract copy and `ash-techtree-openapi.ts`. The command metadata must list only notebook `init` and `pair` under the Techtree group.
