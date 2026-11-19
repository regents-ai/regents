defmodule RegentSprites.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Fly Sprites machines for Regent Elixir apps: create, checkpoint, restore, run commands and move files."

  def project do
    [
      app: :regent_sprites,
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
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"}
    ]
  end
end
