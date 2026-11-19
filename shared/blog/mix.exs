defmodule RegentBlog.MixProject do
  use Mix.Project

  def project do
    [
      app: :regent_blog,
      version: "0.2.0",
      elixir: "~> 1.20",
      description: "File-authored Markdown blog catalogs for Regent Phoenix products",
      deps: [
        {:mdex, "== 0.14.6"},
        {:yaml_elixir, "~> 2.12"},
        {:floki, "~> 0.38"}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
