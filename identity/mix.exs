defmodule RegentIdentity.MixProject do
  use Mix.Project

  # regent_privy, pinned to the same published elixir-utils commit as the site.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "240e93856f11ae2f7be0b427ef8eb8a468afb4f2"

  def project do
    [
      app: :regent_identity,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:ash, "~> 3.34 and >= 3.34.3"},
        # ash_postgres main with #910, the commit platform/mix.exs pins, until a Hex
        # release carries it: 2.10.0 through 2.15.2 send upserts and update_many to the
        # public schema, ignoring the repo's prefix that picks each site's schema on
        # the shared database.
        {:ash_postgres,
         git: "https://github.com/ash-project/ash_postgres.git",
         ref: "55db7d449aad351d200c5f300fca2a83e0a8734c"},
        {:simple_sat, "~> 0.1"},
        {:plug, "~> 1.19"},
        {:regent_privy, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "privy"}
      ],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
  def cli, do: [preferred_envs: [check: :test]]
end
