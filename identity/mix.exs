defmodule RegentIdentity.MixProject do
  use Mix.Project

  # regent_privy, pinned to the same published elixir-utils commit as the site.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "9ca24b0485cd734644a1f790cee1d6b62938eb57"

  def project do
    [
      app: :regent_identity,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:ash, "~> 3.33.0"},
        {:ash_postgres, "~> 2.13"},
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
