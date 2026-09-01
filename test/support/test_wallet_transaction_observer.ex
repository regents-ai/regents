defmodule AshPlatform.TestWalletTransactionObserver do
  @moduledoc false

  @behaviour AshPlatform.WalletActions.TransactionObserver

  # A test says what Base answered, and nothing else does. Without a watcher the
  # observation is unavailable, so a test that forgot to arrange an outcome can
  # never fabricate a confirmed transaction.
  @impl true
  def observe(transaction, scope) do
    case Application.get_env(:ash_platform, :test_wallet_observation_watcher) do
      nil ->
        :unavailable

      watcher ->
        send(watcher, {:wallet_observation, scope, transaction, self()})

        receive do
          {:wallet_observation_result, :crash} -> raise "simulated Base observation crash"
          {:wallet_observation_result, result} -> result
        after
          5_000 -> :unavailable
        end
    end
  end
end
