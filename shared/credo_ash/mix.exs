defmodule CredoAsh.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Credo checks for Ash Framework anti-patterns, encoding the ash-regents playbook."

  def project do
    [
      app: :credo_ash,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:credo, "~> 1.7"}
    ]
  end
end
