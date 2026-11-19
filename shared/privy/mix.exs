defmodule RegentPrivy.MixProject do
  use Mix.Project

  @version "0.2.1"
  @description "Shared Privy sign-in for Regent Elixir apps: token verification, the request pair, owners-only pages and the browser sign-in."

  def project do
    [
      app: :regent_privy,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
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
      {:joken, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:phoenix_live_view, "~> 1.1"}
    ]
  end
end
