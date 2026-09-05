defmodule AshPlatform.TestBrowserWalletTransactionObserver do
  @moduledoc false

  @behaviour AshPlatform.WalletActions.TransactionObserver

  # The Playwright server has no test process to ask, so the browser proofs name
  # the outcome in the hash they submit: an all-f hash is the canonical revert
  # and every other well-formed hash confirms. Only the browser server selects
  # this; ExUnit uses the observer that answers nothing on its own.
  @impl true
  def observe(%{"hash" => "0x" <> hash}, _scope) do
    if String.starts_with?(hash, String.duplicate("f", 62)), do: :reverted, else: :success
  end

  def observe(_transaction, _scope), do: :unavailable
end
