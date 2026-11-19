defmodule RegentAgents.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Regent Agents: one pairing between a person and their agent, shared by every Regent site."

  def project do
    [
      app: :regent_agents,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp deps do
    [
      {:ash, "~> 3.36"},
      # Regent's copy of 2.15.2 with ash-project/ash_postgres#910: upserts use the
      # repo's prefix, which picks each site's schema on the shared database.
      {:ash_postgres,
       git: "https://github.com/regents-ai/ash_postgres.git",
       ref: "cc886ab3efc8b05d51b7b1f57e609341fb6a0873"},
      {:postgrex, "~> 0.22"},
      {:simple_sat, "~> 0.1"},
      {:plug, "~> 1.19"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:phoenix_pubsub, "~> 2.1"},
      {:siwa,
       git: "https://github.com/regents-ai/elixir-utils.git",
       ref: "23bb83df91f7ce86a24eea27c599adfb23e27b41",
       sparse: "siwa/siwa-elixir/apps/siwa"},
      {:regent_format, path: "../../format"}
    ]
  end
end
