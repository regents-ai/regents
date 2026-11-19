defmodule RegentIdentity.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Regent Identity: one shared profile per person, used by every Regent site."

  def project do
    [
      app: :regent_identity,
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
      {:simple_sat, "~> 0.1"},
      {:plug, "~> 1.19"},
      {:regent_privy, path: "../../privy"},
      {:regent_format, path: "../../format"}
    ]
  end
end
