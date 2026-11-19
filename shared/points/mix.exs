defmodule RegentPoints.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_points,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:regent_agents, path: "../ash_components/agents"},
      {:ash, "~> 3.36"},
      # Regent's copy of 2.15.2 with ash-project/ash_postgres#910: upserts use the
      # repo's prefix, which picks each site's schema on the shared database.
      {:ash_postgres,
       git: "https://github.com/regents-ai/ash_postgres.git",
       ref: "cc886ab3efc8b05d51b7b1f57e609341fb6a0873"},
      {:simple_sat, "~> 0.1"},
      {:oban, "~> 2.24"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.3"},
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:regent_format, path: "../format"},
      {:postgrex, "~> 0.22"}
    ]
  end
end
