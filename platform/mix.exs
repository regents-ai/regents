defmodule Regents.MixProject do
  use Mix.Project

  # Shared Regent libraries. Twelve elixir-utils packages are this repository's own
  # folders under ../shared; siwa and regent_chain, and design-system's regent_ui, stay
  # pinned to one published commit. To move a pin, change its ref and run
  # `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "6d98a1139caf6a89e7b358070ea1165306d2f47b"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "fe5039667b5402fb43be9f506345f49ed4121a2f"

  def project do
    [
      app: :regents,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: false,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      compilers: [:boundary, :ash_signals, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Regents.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:castore, "~> 1.0"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.6", override: true},
      {:ash, "~> 3.37"},
      # ash_postgres at its v2.16.0 tag, which carries #910: upserts use the repo's
      # prefix, which picks each site's schema on the shared database.
      {:ash_postgres,
       git: "https://github.com/ash-project/ash_postgres.git",
       ref: "e36aa20a9f000f3f3bd89b0816fa9460156cb13c",
       override: true},
      {:oban, "~> 2.24"},
      {:nebulex, "~> 3.0"},
      {:nebulex_local, "~> 3.0"},
      {:ash_oban, "~> 0.10.3"},
      {:ash_phoenix, "~> 2.3.26"},
      {:igniter, "== 0.8.5", only: :dev, runtime: false},
      {:usage_rules, "~> 1.3", only: :dev, runtime: false},
      {:mdex, "== 0.14.6"},
      {:floki, "== 0.38.5"},
      {:ens_elixir, path: "../shared/ens"},
      # idna 8 fixes EEF-CVE-2026-117678; ethers and jsv still ask for idna 7.
      {:idna, "~> 8.0", override: true},
      # ens_elixir and regent_agents name the same siwa pin.
      {:siwa,
       git: @elixir_utils,
       ref: @elixir_utils_ref,
       sparse: "siwa/siwa-elixir/apps/siwa",
       override: true},
      {:regent_privy, path: "../shared/privy", override: true},
      {:regent_identity, path: "../shared/ash_components/identity"},
      {:regent_payments, path: "../shared/ash_components/payments"},
      {:regent_agents, path: "../shared/ash_components/agents", override: true},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_blog, path: "../shared/blog"},
      {:regent_agent_access, path: "../shared/agent_access", override: true},
      {:regent_oauth,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "oauth", override: true},
      {:regent_mcp_agents, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "mcp_agents"},
      {:regent_mcp_events, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "mcp_events"},
      {:ash_ai, "~> 1.5"},
      {:assent, "== 0.3.2"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:tz, "~> 0.28"},
      {:cachex, "~> 4.1"},
      {:jsv, "~> 0.27"},
      {:x402, "0.9.0"},
      {:ethers, "0.8.0"},
      {:regent_format, path: "../shared/format", override: true},
      # regent_payments names the same regent_chain pin.
      {:regent_chain,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain", override: true},
      {:regent_points, path: "../shared/points"},
      # The site's crash saving (RegentHttp.ErrorSaving).
      {:regent_http, path: "../shared/http", override: true},
      {:regent_sprites, path: "../shared/sprites"},
      {:picosat_elixir, "~> 0.2.3"},
      {:simple_sat, "~> 0.1"},
      {:sourceror, "~> 1.12", only: :dev, runtime: false},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:logger_json, "~> 7.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:peep, "~> 5.0"},
      {:telemetry_poller, "~> 1.3"},
      {:error_tracker, "~> 0.9"},
      {:jason, "~> 1.2"},
      # Ethereum Keccak-256 for EIP-55, which OTP's NIST `:sha3_256` is not.
      {:jose, "~> 1.11.13"},
      {:ex_keccak, "~> 0.7.8"},
      {:yaml_elixir, "== 2.12.2"},
      # Keyfleet's, ahead of its port: nothing in the site uses them yet.
      {:ash_state_machine, "~> 0.3.1"},
      {:mint, "~> 1.11"},
      {:mint_web_socket, "~> 1.0"},
      {:ex_image_info, "~> 1.0"},
      # Patchbay's: works out a site's main address (shop.example.co.uk belongs to example.co.uk).
      {:domainatrex, "~> 3.2"},
      # Patchbay's search room; already in the lock through the web request library.
      {:nimble_pool, "~> 1.1"},
      # Techtree's Wallet Bench results.zip streaming downloads.
      {:zstream, "~> 0.6.7"},
      {:decimal, "== 3.2.0"},
      {:req, "== 0.7.5"},
      {:vix, "~> 0.42.0"},
      {:bandit, "~> 1.14"},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: :dev, runtime: false},
      {:credo_ash, path: "../shared/credo_ash", only: :dev, runtime: false},
      {:sobelow, "~> 0.16", only: :dev, runtime: false},
      # Each product's code may use the site, the shared chain plumbing and Account's
      # exports, never another product (`use Boundary` in each product's root module).
      {:boundary, "~> 0.12.0", runtime: false}
    ]
  end

  # `mix usage_rules.sync` writes the marked block at the end of AGENTS.md: how to
  # read the installed version's docs, and links to each package's own rules in deps/.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        {:usage_rules, sub_rules: []},
        {:usage_rules, sub_rules: :all, main: false, link: :markdown},
        {:ash, link: :markdown},
        {~r/^ash_/, link: :markdown},
        {:phoenix, sub_rules: ["phoenix", "liveview", "html"], link: :markdown}
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "cmd npm ci", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "regent_ui.assets",
        "regent_blog.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
        "esbuild regents"
      ],
      "assets.deploy": [
        "regent_ui.assets",
        "regent_blog.assets",
        "regent_identity.assets",
        "regent_agent_access.assets",
        "esbuild regents --minify",
        "phx.digest"
      ],
      # Regents' migration ledger is regents_app.schema_migrations, the one
      # Regents.Repo.migrate!/2 and the release use. The stock commands read and
      # write that ledger, and run each migration in that schema, only with this
      # prefix. A folded product's migrations are applied locally by
      # `mix regents.setup_local_auth`.
      "ecto.migrate": ["ecto.migrate --prefix regents_app"],
      "ecto.rollback": ["ecto.rollback --prefix regents_app"],
      "ecto.migrations": ["ecto.migrations --prefix regents_app"],
      # Each folded product's migrations and snapshots go to its own folders.
      "ash.codegen": ["regents.codegen"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "cmd mix hex.audit",
        "format --check-formatted",
        "credo --strict",
        "cmd env SOBELOW_HOME=_build/sobelow mix sobelow --exit",
        # The measured compile-connected baseline; lower it whenever references are removed.
        # ErrorTracker's dashboard route adds one link: the router reads its on_mount at compile time.
        # Messages adds four, as every Ash domain does: the domain reads its resource, and the
        # resource its two policy checks and its `run` module. Updates adds one: the domain
        # reads its resource. Techtree's Model Climb adds one the same way, and Techtree's
        # catalog three: its domain reads its three resources. Techtree's run log adds five:
        # its domain reads its three resources, an entry its embedded assessment, and the
        # assessment its embedded Skill change. Patchbay's tables add forty: its six domains
        # read their thirty-nine resources, and a report its embedded cve.now facts. The
        # pairing read adds two: its domain reads its resource, and the resource its check.
        # Autolaunch's tables add thirty-one: its two domains read their thirty-one resources.
        # Techtree's Wallet Bench adds six: its domain reads its six resources.
        # Keyfleet's core adds one hundred: 61 a domain reading its resource, 34 a resource its policy check, 5 others.
        # The Account views add three: two domains each read their new resource, and the
        # pairing view its policy check.
        # Keyfleet's page layer adds one: its route catalog builds its list from the fleet
        # catalog as it compiles.
        # Keyfleet's fleet pages add one: the router reads that route catalog as it compiles.
        # Techtree's Projects add one: its domain reads its resource.
        # Techtree's Enquiries and Watchdog add three (domains reading resources), and
        # AgentBodyReader sizing Techtree publications adds one in Endpoint.
        # Keyfleet's AgentTools workspace read domain adds two (domain -> workspace -> read).
        # Autolaunch's full write/agent/stocks/covered-calls/earn/exposure domains add 54
        # (Ash domains reading resources and resources reading their policy checks/changes/validations).
        # Patchbay's full write/assist/offers/wallet-bench domains add 15 (7 WalletBench view resources
        # plus 8 resource->check/notifier/action compile edges).
        # Unified /mcp and OAuth add 4 (Agents->Connection, Connection->Caller,
        # Patchbay.AgentTools->Forum, and McpAgent->ClientAddress).
        # Patchbay's internal writes check the system actor on Report and Reply.
        # The Endpoint passes the launch-gated Markdown lookup to RegentAgentAccess.
        # Hosted product tools add seven intentional links: three tool domain-to-resource
        # links, two Autolaunch domain-to-preparer links and each preparer's launch check.
        # Keyfleet's full hosted MCP surface adds twenty-six intentional links: twelve new
        # Keyfleet.AgentTools domain-to-resource links, thirteen resource-to-Run action links,
        # and Keyfleet.Graph reading Keyfleet.Capabilities for AshAi tool descriptions.
        "xref graph --label compile-connected --fail-above 351",
        "ash.codegen --check",
        "usage_rules.sync --check",
        "regents.route_handoff --check"
      ]
    ]
  end
end
