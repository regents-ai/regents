defmodule Regents.Techtree.WalletBench.BaseRpc do
  @moduledoc """
  Token amounts as the bench's pages write them. The bench's calls to Base stay
  on techtree.sh with the bench that makes them.
  """

  @doc "A token amount in whole tokens, such as `0.25` for 250000 USDC units."
  @spec decimal(non_neg_integer(), non_neg_integer()) :: String.t()
  def decimal(amount, decimals) do
    amount
    |> Decimal.new()
    |> Decimal.div(Integer.pow(10, decimals))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
