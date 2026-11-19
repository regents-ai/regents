defmodule RegentHttp.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Shared Req HTTP client conventions for Regent Elixir apps."

  def project do
    [
      app: :regent_http,
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
      {:req, "~> 0.7"},
      # RegentHttp.Public connects to an address it has already checked.
      {:mint, "~> 1.11"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.0"},
      # RegentHttp.ErrorSaving runs ErrorTracker's handlers; a site brings ErrorTracker.
      {:error_tracker, "~> 0.9", optional: true}
    ]
  end
end
