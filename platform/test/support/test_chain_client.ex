defmodule AshPlatform.TestChainClient do
  @moduledoc """
  The chain wallet steps are read on, in tests. A sent step is on it once a test
  names it: a hash with no transaction is still waiting, and one with no receipt
  has not landed yet.
  """
  @behaviour AshPlatform.ChainClient

  @impl true
  def transaction(_chain, hash), do: sent(:test_chain_transactions, hash)

  @impl true
  def receipt(_chain, hash), do: sent(:test_chain_receipts, hash)

  defp sent(key, hash),
    do: {:ok, :ash_platform |> Application.get_env(key, %{}) |> Map.get(hash)}
end
