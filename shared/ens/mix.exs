defmodule AgentEns.MixProject do
  use Mix.Project

  @version "0.1.1"
  @description "Elixir-first ENSIP-25 library for ENS and ERC-8004 verification, planning, and unsigned link preparation."

  def project do
    [
      app: :ens_elixir,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir, :app],
      description: @description,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:idna, "~> 8.0"},
      {:jason, "~> 1.4"},
      {:siwa,
       git: "https://github.com/regents-ai/elixir-utils.git",
       ref: "23bb83df91f7ce86a24eea27c599adfb23e27b41",
       sparse: "siwa/siwa-elixir/apps/siwa"},
      {:ex_keccak, "~> 0.7.8"}
    ]
  end
end
