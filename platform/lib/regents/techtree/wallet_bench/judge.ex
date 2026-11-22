defmodule Regents.Techtree.WalletBench.Judge do
  @moduledoc """
  The judge model's name, as the Wallet Bench page shows it. The judging stays
  on techtree.sh, whose configuration names this model.
  """

  @doc "The model that rules on each turn."
  @spec model() :: String.t()
  def model, do: "claude-opus-5-5"
end
