# Regents

Own regents.sh, its API, CLI and Regents contracts in this monorepo.

- `platform/`: Phoenix/Ash application. Read its instructions for web changes.
- `cli/`: CLI workspace; its API/JSON contracts and generated bindings stay local.
- `contracts/`: Solidity, staking/distribution and retained historical evidence.
- Shared UI and Elixir libraries remain separate siblings. Use `REGENT_DEPS_ROOT`
  for isolated builds. Run checks from the owning component or use root Make targets.
- Follow Control's `regent-workflow`; use one integrating owner for this repository.
  Scope verification to observable acceptance and preserve useful regression coverage.
- Preserve uncommitted work, public command/API shapes and protected source evidence.
  Every distinct wallet press reaches the wallet. No signing, production access,
  deployment or publishing without applicable founder authority. Never read `.env`,
  `.env.local` or `.envrc`.

For product orientation and related Regent products, see [README.md](README.md).
The public agent entry point is [platform/priv/static/llms.txt](platform/priv/static/llms.txt);
keep its advertised commands consistent with the owning CLI and HTTP contracts.
