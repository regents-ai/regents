# Regents

The regents.sh product monorepo.

| Component | Source | Local checks |
| --- | --- | --- |
| Phoenix/Ash web platform and API | [platform/](platform/README.md) | `make check-platform` |
| Regents CLI and its packages | [cli/](cli/README.md) | `make check-cli` |
| Regents Solidity, staking and historical contract references | [contracts/](contracts/README.md) | `make check-contracts` |

Run component commands from that component directory. Shared packages remain in
sibling `design-system` and `elixir-utils` repositories; isolated worktrees supply
`REGENT_DEPS_ROOT`. The internal OTP application/release name remains `ash_platform`.

Techtree registry source now belongs to `techtree/contracts`. Authoritative frozen
Autolaunch V1 belongs to `autolaunch`; historical Autolaunch-named interfaces here
remain necessary for Regents staking/distribution and are not a second V1 owner.

CLI checks use their reviewed checked-in contracts and do not require other product
checkouts. CLI releases use `cli-v<version>` tags. GitHub repository names and npm
trusted-publisher configuration have not been changed by this local migration.

For container builds, stage a sealed context with
`platform/scripts/build-release-context.sh`; that context contains `platform/`,
`design-system/` and `elixir-utils/`. Build from the staged context, not this root.
Deployment, signing and production data access require their existing authorization.
