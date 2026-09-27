# regents.sh platform

Agent improvement, revenue, and independence. Staking of $REGENT on Base for a pro rata share of USDC from the products & platforms.
Regents is also the starting point for the Regents Labs family: launch with
Autolaunch, investigate agent tools with Patchbay, and evaluate Skills with Techtree.

The main Regent web application, built by Regents Labs on Phoenix, LiveView,
and Ash. It serves the public site, the signed-in product shell, and the public HTTP API, and
it owns $REGENT staking and yield, Animata pass redemption, human <> agent linking, and is a
general informational directory for the varied apps and products made by Regents Labs.

[Website](https://regents.sh) · [CLI](https://github.com/regents-ai/regents-cli) · [API](platform/contracts/api-contract.openapiv3.yaml) · [Star on GitHub](https://github.com/regents-ai/regents)

## Start here

- **Explore the product:** visit [regents.sh](https://regents.sh). Product routes
  are enabled by deployment configuration; the homepage does not imply that every
  signed-in feature is open.
- **Use an agent or terminal:** start with the [CLI guide](https://github.com/regents-ai/regents-cli#readme) and
  [agent wallet guide](https://github.com/regents-ai/regents-cli/blob/main/docs/agent-wallets.md). Older cross-product commands are
  documented separately from the independently owned product CLIs.
- **Contribute:** choose a component below. Web work does not require downloading
  recursive Solidity dependencies. Use [AGENTS.md](AGENTS.md) for repository boundaries.

| Component | Source | Verification |
| --- | --- | --- |
| Phoenix/LiveView/Ash website and API | [platform/](platform/README.md) | `make check-platform` |
| Solidity, staking and contract history | [contracts/](contracts/README.md) | `make check-contracts` |
| Shared identity domain used by every product | [identity/](identity/README.md) | `mix check` from `identity/`, see its README |
| Agent runtime plugins | [plugins/](plugins/README.md) | None yet; runtime integrations ship with the [Regents CLI](https://github.com/regents-ai/regents-cli) |

Run setup from the owning component. `identity/` is the one shared package that
lives in this repository; the other shared libraries are independent repositories, and
[platform setup](platform/README.md#quickstart) explains their paths. The platform's
OTP application and release are both named `regents`.

## Current boundaries

The monorepo contains retained Formation routes while that product cutover is in
progress. Autolaunch lives in its own monorepo and has no pages, endpoints or contract
interfaces here. Techtree registry source belongs to `techtree/contracts`.

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
