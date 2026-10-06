defmodule RegentAgents.MixProject do
  use Mix.Project

  # siwa, pinned to the same published elixir-utils commit as the site.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "f344888c70bd5983ff8a27339ac2db9a71594bd2"

  def project do
    [
      app: :regent_agents,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:ash, "~> 3.34 and >= 3.34.3"},
        # 2.13.1 through 2.14.2 send upserts to the public schema, ignoring the
        # repo's prefix that picks each site's schema on the shared database.
        {:ash_postgres, "== 2.13.0"},
        {:postgrex, "~> 0.22"},
        {:simple_sat, "~> 0.1"},
        {:plug, "~> 1.19"},
        {:req, "~> 0.5"},
        {:jason, "~> 1.4"},
        {:phoenix_pubsub, "~> 2.1"},
        {:siwa, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "siwa/siwa-elixir/apps/siwa"}
      ],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
  def cli, do: [preferred_envs: [check: :test]]
end
