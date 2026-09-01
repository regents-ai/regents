defmodule AshPlatform.TestWalletTransactionObserver do
  @behaviour AshPlatform.WalletActions.TransactionObserver

  @impl true
  def observe(%{"hash" => "0x" <> hash}, _scope) do
    if String.starts_with?(hash, String.duplicate("f", 62)), do: :reverted, else: :success
  end

  def observe(_transaction, _scope), do: :unavailable
end
