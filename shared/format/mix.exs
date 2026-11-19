defmodule RegentFormat.MixProject do
  use Mix.Project

  @version "0.2.0"
  @description "Shared display formatting helpers for Regent Elixir apps."

  def project do
    [
      app: :regent_format,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:decimal, "~> 3.1"}
    ]
  end
end
