defmodule RegentAllowance.MixProject do
  use Mix.Project

  # regent_openai's result structs, pinned to the same published elixir-utils
  # commit as the site. regent_openai names regent_http by a sibling path; this
  # pin replaces it.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "cfe5fb3638f8e63827c6ed79a7bd5d25078f073e"

  def project do
    [
      app: :regent_allowance,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:ash, "~> 3.33.0"},
        {:ash_postgres, "~> 2.13"},
        {:simple_sat, "~> 0.1"},
        {:decimal, "~> 3.1"},
        {:regent_openai, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "openai"},
        {:regent_http, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "http", override: true}
      ],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger]]
  def cli, do: [preferred_envs: [check: :test]]
end
