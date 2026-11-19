defmodule RegentAgentAccess.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_agent_access,
      version: "0.2.0",
      elixir: "~> 1.20",
      description:
        "Accept negotiation, Vary merging and recovery responses for Regent Phoenix products",
      deps: [
        {:phoenix, "~> 1.8"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
