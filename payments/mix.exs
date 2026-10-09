defmodule RegentPayments.MixProject do
  use Mix.Project

  # regent_chain and regent_format, pinned to the same published elixir-utils
  # commit as the site and the identity library.
  @elixir_utils "https://github.com/regents-ai/elixir-utils.git"
  @elixir_utils_ref "58acbc4742ea8acded42e8fb40816ac6e0400aaa"

  def project do
    [
      app: :regent_payments,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:ash, "~> 3.34 and >= 3.34.3"},
        # 2.13.1 through 2.14.2 send upserts to the public schema, ignoring the
        # repo's prefix that picks each site's schema on the shared database.
        {:ash_postgres, "== 2.13.0"},
        {:simple_sat, "~> 0.1"},
        {:x402, "0.9.0"},
        {:ethers, "0.8.0"},
        {:ex_secp256k1, "~> 0.8.0"},
        {:ex_keccak, "~> 0.7.8"},
        {:finch, "~> 0.19"},
        {:req, "~> 0.5"},
        {:plug_crypto, "~> 2.1"},
        {:regent_chain, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "chain"},
        {:regent_format, git: @elixir_utils, ref: @elixir_utils_ref, sparse: "format"},
        {:bandit, "~> 1.5", only: :test}
      ],
      aliases: [check: ["compile --warnings-as-errors", "format --check-formatted", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
  def cli, do: [preferred_envs: [check: :test]]
end
