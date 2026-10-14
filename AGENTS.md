# Regents

Own regents.sh, its API and Regents contracts in this monorepo. The `regents` CLI lives in
the separate regents-cli repository.

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `contracts/`: Solidity, staking/distribution and retained historical evidence.
- `identity/`: shared Ash identity domain and `regent_identity` schema consumed by every
  product. Read its README before changing sync, actor or ownership rules.
- `plugins/`: home for standalone runtime plugin packages; none exist yet. Hermes,
  OpenClaw, MCP and bundled-skill integrations are CLI code in regents-cli.
- Shared UI and Elixir libraries other than `identity/` come from GitHub, each pinned to
  one commit in `platform/mix.exs`.
- `make check` runs every component gate; `make check-platform`, `check-required-fixes`,
  `check-identity` and `check-contracts` run one. `MIX_TEST_PARTITION` (an underscore and
  a short id, unique to your working tree) is required.
- Follow the workspace's `regent-workflow`; use one integrating owner for this repository.
  Scope verification to observable acceptance and preserve useful regression coverage.
- Preserve uncommitted work, public command/API shapes and protected source evidence.
  Every distinct wallet press reaches the wallet. No signing, production access,
  deployment or publishing without applicable founder authority. Never read `.env`,
  `.env.local` or `.envrc`.

For product orientation and related Regent products, see [README.md](README.md).
The public agent entry point is [platform/priv/public/llms.md](platform/priv/public/llms.md), served at `/llms.txt`;
keep its advertised commands consistent with the owning CLI and HTTP contracts.

<!-- BEGIN REGENT ROLLOUT REVIEW -->
## Code Review Rules

### Human and agent guidance drift

For every code review, read `.agents/skills/rollout-guidance-check/SKILL.md` and assess the diff's guidance
impact, even when no prose files changed. Trace affected behavior into public docs,
product/developer Skills, human-to-agent prompts, tooltips and other UI copy,
WebMCP/MCP schemas and descriptions, CLI help/errors/examples, OpenAPI, manifests
and generated or bundled copies. Shared behavior starts in ash-template and its
libraries; inspect affected consumers when available.

Report concrete mismatches introduced or made relevant by this change, with the
failing user/agent action and exact source locations. Distinguish source, packaged,
published and deployed versions; name missing cross-repository or live evidence.
Preserve dated history and avoid cosmetic findings. Do not inflate severity or
claim that no findings proves complete coverage. This is read-only review: never
sign, pay, activate earnings, publish or deploy to test an instruction.
<!-- END REGENT ROLLOUT REVIEW -->
