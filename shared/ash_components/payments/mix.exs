defmodule RegentPayments.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Regent Payments: paid actions for every Regent site, in USDC on Base."

  def project do
    [
      app: :regent_payments,
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
       ref: "cc886ab3efc8b05d51b7b1f57e609341fb6a0873",
       override: true},
      {:simple_sat, "~> 0.1"},
      {:x402, "0.9.0"},
      {:ethers, "0.8.0"},
      {:ex_secp256k1, "~> 0.8.0"},
      {:ex_keccak, "~> 0.7.8"},
      {:finch, "~> 0.19"},
      {:req, "~> 0.5"},
      {:plug_crypto, "~> 2.1"},
      {:regent_chain,
       git: "https://github.com/regents-ai/elixir-utils.git",
       ref: "6d98a1139caf6a89e7b358070ea1165306d2f47b",
       sparse: "chain"},
      {:regent_agents, path: "../agents"}
    ]
  end
end
