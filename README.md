# regents.sh platform

We build platforms for persistent agents. All revenue is converted to USDC and split with
$REGENT stakers, who stake on Base for a pro rata share. Regents is also the starting point
for the Regents Labs family: launch with Autolaunch, get agents unstuck with Patchbay, build
better agents with Techtree, join a fleet with Keyfleet, and, once it is released, run a
private agent stack with Cloak.

The main Regent web application, built by Regents Labs on Phoenix, LiveView,
and Ash. It serves the public site, the signed-in product shell, and the public HTTP API, and
it owns $REGENT staking and yield, Animata pass redemption, human <> agent linking, and is a
general informational directory for the varied apps and products made by Regents Labs.

[Website](https://regents.sh) · [CLI](https://github.com/regents-ai/regents-cli) · [API](platform/contracts/api-contract.openapiv3.yaml) · [Star on GitHub](https://github.com/regents-ai/regents)

## Start here

- **Explore the product:** visit [regents.sh](https://regents.sh). Product routes
  are enabled by deployment configuration; the homepage does not imply that every
  signed-in feature is open.
- **Use an agent or terminal:** start with the [CLI guide](https://github.com/regents-ai/regents-cli#readme)
  and its [site commands](https://github.com/regents-ai/regents-cli/blob/main/docs/site-commands.md).
- **Contribute:** choose a component below. Web work does not require downloading
  recursive Solidity dependencies. Use [AGENTS.md](AGENTS.md) for repository boundaries.

| Component | Source | Verification |
| --- | --- | --- |
| Phoenix/LiveView/Ash website and API | [platform/](platform/README.md) | `make check-platform` |
| Solidity, staking and contract history | [contracts/](contracts/README.md) | `make check-contracts` |
| Agent runtime plugins | [plugins/](plugins/README.md) | None yet; runtime integrations ship with the [Regents CLI](https://github.com/regents-ai/regents-cli) |

Run setup from the owning component. Twelve shared Elixir libraries, the shared profile
among them, are copied into [shared/](shared/), from the library commit
[shared/SOURCE.json](shared/SOURCE.json) records; a newer library commit is taken in by
copying the packages again from it and moving that commit. The rest are independent
repositories, and [platform setup](platform/README.md#shared-dependencies) explains how
each is used. The platform's OTP application and release are both named
`regents`.

## Current boundaries

The Formation code still backs public Regent profiles and has no routes of its own.
Autolaunch lives in its own repository: this site shows its product page at `/autolaunch`,
and `contracts/src/autolaunch` keeps the source of its first (V1) contracts. Techtree
registry source belongs to `techtree/contracts`.

Shared profile and historical-claim restoration work must pass its own migration and
ownership checks before it is described as released. A CLI build, API schema or UI
preview is not evidence of a deployed capability.

## Related products

| Product | Use it for | Website | Source |
| --- | --- | --- | --- |
| Regents | Agent identity, operations, staking and redemption | [regents.sh](https://regents.sh) | [Regents](https://github.com/regents-ai/regents) |
| Autolaunch | Token auctions and launch operations | [autolaunch.sh](https://autolaunch.sh) | [Autolaunch](https://github.com/regents-ai/autolaunch) |
| Patchbay | Agent tool reports and bounded WebMCP repair | [patchbay.help](https://patchbay.help) | [Patchbay](https://github.com/regents-ai/patchbay) |
| Techtree | Custom Skills, evals, environments and models, with results you can measure | [techtree.sh](https://techtree.sh) | [Techtree](https://github.com/regents-ai/techtree) |
| Keyfleet | A persistent team for your agent, owned by its Key holders | [keyfleet.ai](https://keyfleet.ai) | — |
| Cloak | A private agent stack for the Mac, in development | [regents.sh/cloak](https://regents.sh/cloak) | — |

Each product owns its API, CLI and authorization. A login, payment or published
result on one product does not grant permissions on another. Shared presentation
lives in [design-system](https://github.com/regents-ai/design-system); common Elixir
libraries live in [elixir-utils](https://github.com/regents-ai/elixir-utils), and this
repository keeps its own copies of twelve of them in [shared/](shared/).

## License

See the license in each component. Vendored dependencies retain their own licenses.
