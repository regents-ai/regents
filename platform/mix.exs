defmodule Regents.MixProject do
  use Mix.Project

  # Shared Regent libraries, each pinned to one published commit. To move a pin,
  # change its ref and run `mix deps.update <name>`.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "72ccfea10551436a9b7aaad29d3ec6b5462d423f"
  @design_system "https://github.com/regents-ai/design-system.git"
  @design_system_ref "5b4f47ec731840a36994d7cdd1464070f803362b"

  def project do
    [
      app: :regents,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: false,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      compilers: [:ash_signals, :phoenix_live_view] ++ Mix.compilers(),
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

  def cli do
    [
      preferred_envs: [precommit: :test, "test.external": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:castore, "~> 1.0"},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.6", override: true},
      {:ash, "~> 3.36"},
      # 2.13.1 through 2.14.5 send upserts to the public schema, ignoring the
      # repo's prefix that picks each site's schema on the shared database.
      {:ash_postgres, "== 2.13.0"},
      {:oban, "~> 2.24"},
      {:nebulex, "~> 3.0"},
      {:nebulex_local, "~> 3.0"},
      {:ash_oban, "~> 0.10.0"},
      {:ash_phoenix, "~> 2.3.25"},
      {:igniter, "== 0.8.4", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2.8", only: [:dev, :test], runtime: false},
      {:mdex, "== 0.14.2"},
      {:ens_elixir, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ens"},
      # ens_elixir names siwa by a sibling path; this pin replaces it.
      {:siwa,
       git: @elixir_utils,
       ref: @elixir_utils_ref,
       sparse: "siwa/siwa-elixir/apps/siwa",
       override: true},
      {:regent_privy,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy", override: true},
      {:regent_identity, path: "../identity"},
      {:regent_payments,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/payments"},
      {:regent_agents,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "ash_components/agents", override: true},
      {:regent_ui, git: @design_system, ref: @design_system_ref, sparse: "regent_ui"},
      {:regent_blog, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "blog"},
      {:regent_agent_access, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "agent_access"},
      {:regent_format,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format", override: true},
      # regent_credits names regent_chain by a sibling path; this pin replaces it.
      {:regent_chain,
       git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain", override: true},
      {:regent_credits, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "credits"},
      {:regent_points, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "points"},
      {:regent_sprites, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "sprites"},
      {:picosat_elixir, "~> 0.2.3"},
      {:simple_sat, "~> 0.1"},
      {:sourceror, "~> 1.12", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.13", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:peep, "~> 5.0"},
      {:telemetry_poller, "~> 1.3"},
      {:error_tracker, "~> 0.9"},
      {:jason, "~> 1.2"},
      # Ethereum Keccak-256 for EIP-55, which OTP's NIST `:sha3_256` is not.
      {:jose, "~> 1.11.12"},
      {:decimal, "== 3.2.0"},
      {:req, "== 0.7.5"},
      {:vix, "~> 0.42.0"},
      # CVE-2026-105659 is fixed from 1.13.1.
      {:bandit, "~> 1.13.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:credo_ash,
       git: @elixir_utils,
       ref: @elixir_utils_ref,
       sparse: "credo_ash",
       only: [:dev, :test],
       runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false}
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
      # Regents.Repo.migrate!/1 and the release use. The stock commands read and
      # write that ledger, and run each migration in that schema, only with this prefix.
      "ecto.migrate": ["ecto.migrate --prefix regents_app"],
      "ecto.rollback": ["ecto.rollback --prefix regents_app"],
      "ecto.migrations": ["ecto.migrations --prefix regents_app"],
      # The test database is prepared before the site starts, since its Oban
      # refuses to start without its tables.
      test: ["ecto.create --quiet", "regents.setup_local_auth", "test"],
      "test.external": ["test --only external"],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --check-unused",
        "cmd mix hex.audit",
        "format --check-formatted",
        "credo --strict",
        "cmd env SOBELOW_HOME=_build/sobelow mix sobelow --exit",
        # The measured compile-connected baseline; lower it whenever references are removed.
        # ErrorTracker's dashboard route adds one link: the router reads its on_mount at compile time.
        "xref graph --label compile-connected --fail-above 38",
        "test --warnings-as-errors",
        "ash.codegen --check",
        "usage_rules.sync --check",
        "regents.route_handoff --check"
      ]
    ]
  end
end
