defmodule RegentIdentity.MixProject do
  use Mix.Project

  def project do
    shared = System.get_env("REGENT_DEPS_ROOT", Path.expand("../..", __DIR__))

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
        {:regent_privy,
         path: System.get_env("REGENT_PRIVY_PATH", Path.join(shared, "elixir-utils/privy"))}
      ],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
  def cli, do: [preferred_envs: [check: :test]]
end
