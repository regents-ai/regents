# Regents

Agent identity and operations, with staking and redemption on Base.
Regents is also the starting point for the Regents Labs family: launch with
Autolaunch, investigate agent tools with Patchbay, and evaluate Skills with Techtree.

[Website](https://regents.sh) · [CLI](cli/README.md) · [API](platform/contracts/api-contract.openapiv3.yaml) · [Star on GitHub](https://github.com/regents-ai/regents)

## Start here

- **Explore the product:** visit [regents.sh](https://regents.sh). Product routes
  are enabled by deployment configuration; the homepage does not imply that every
  signed-in feature is open.
- **Use an agent or terminal:** start with the [CLI guide](cli/README.md) and
  [agent wallet guide](cli/docs/agent-wallets.md). Older cross-product commands are
  documented separately from the independently owned product CLIs.
- **Contribute:** choose a component below. Web and CLI work do not require downloading
  recursive Solidity dependencies. Use [AGENTS.md](AGENTS.md) for repository boundaries.

| Component | Source | Verification |
| --- | --- | --- |
| Phoenix/LiveView/Ash website and API | [platform/](platform/README.md) | `make check-platform` |
| TypeScript CLI and agent integrations | [cli/](cli/README.md) | `make check-cli` |
| Solidity, staking and contract history | [contracts/](contracts/README.md) | `make check-contracts` |
| Shared identity domain used by every product | [identity/](identity/README.md) | `mix check` from `identity/`, see its README |
| Agent runtime plugins | [plugins/](plugins/README.md) | None yet; runtime integrations ship inside the CLI |

Run setup from the owning component. `identity/` is the one shared package that
lives in this repository; the other shared libraries are independent repositories, and
[platform setup](platform/README.md#quickstart) explains their paths. The internal
OTP application/release name remains `ash_platform` so a repository rename does not
change production release identities.

## Current boundaries

The monorepo contains retained Formation and Autolaunch routes while those product
cutovers are in progress. New Autolaunch work belongs to its own monorepo. Techtree
registry source belongs to `techtree/contracts`; retained Autolaunch-named interfaces
here support Regents staking/distribution and are not a second V1 owner.

Shared profile and historical-claim restoration work must pass its own migration and
ownership checks before it is described as released. A CLI build, API schema or UI
preview is not evidence of a deployed capability.

## Related products

| Product | Use it for | Website | Source |
| --- | --- | --- | --- |
| Regents | Agent identity, operations, staking and redemption | [regents.sh](https://regents.sh) | [Regents](https://github.com/regents-ai/regents) |
| Autolaunch | Token auctions and launch operations | [autolaunch.sh](https://autolaunch.sh) | [Autolaunch](https://github.com/regents-ai/autolaunch-contracts) |
| Patchbay | Agent tool reports and bounded WebMCP repair | [patchbay.help](https://patchbay.help) | [Patchbay](https://github.com/regents-ai/patchbay) |
| Techtree | Controlled Skill evaluations and verifiable results | [techtree.sh](https://techtree.sh) | [Techtree](https://github.com/regents-ai/techtree) |

Each product owns its API, CLI and authorization. A login, payment or published
result on one product does not grant permissions on another. Shared presentation
lives in [design-system](https://github.com/regents-ai/design-system); common Elixir
libraries live in [elixir-utils](https://github.com/regents-ai/elixir-utils).

## License

See the license in each component. Vendored dependencies retain their own licenses.
