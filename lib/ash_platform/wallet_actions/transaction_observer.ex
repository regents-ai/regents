defmodule AshPlatform.WalletActions.TransactionObserver do
  @moduledoc false

  alias AshPlatform.WalletActions.Rpc

  @callback observe(map(), :staking | :redemption) ::
              :success | :reverted | :delayed | :unavailable

  @delays [0] ++ List.duplicate(2_000, 15) ++ List.duplicate(10_000, 9)

  def observe(transaction, scope) when scope in [:staking, :redemption] do
    module = Application.get_env(:ash_platform, :wallet_transaction_observer, __MODULE__)

    if module == __MODULE__,
      do: observe_rpc(transaction, scope, @delays),
      else: module.observe(transaction, scope)
  end

  @doc false
  def observe_rpc(transaction, scope, delays) when scope in [:staking, :redemption] do
    case exact_transaction(transaction) do
      {:ok, exact} -> poll(exact, rpc_options(scope), delays)
      :error -> :unavailable
    end
  end

  defp poll(_transaction, _opts, []), do: :delayed

  defp poll(transaction, opts, [delay | remaining]) do
    if delay > 0, do: Process.sleep(delay)

    with {:ok, block} <- Rpc.safe_block(opts),
         {:ok, outcome} <-
           Rpc.canonical_outcome(
             transaction.hash,
             transaction.signer,
             transaction.to,
             transaction.data,
             block,
             opts
           ) do
      case outcome do
        :pending -> poll(transaction, opts, remaining)
        :reverted -> :reverted
        {:success, _logs} -> :success
      end
    else
      _unavailable -> :unavailable
    end
  end

  defp exact_transaction(%{
         "hash" => hash,
         "signer" => signer,
         "to" => to,
         "data" => "0x" <> data
       })
       when is_binary(hash) and is_binary(signer) and is_binary(to) and byte_size(data) <= 16_384 do
    if Rpc.valid_hash?(hash) and String.match?(data, ~r/^[0-9a-fA-F]*\z/) do
      {:ok, %{hash: hash, signer: signer, to: to, data: "0x" <> data}}
    else
      :error
    end
  end

  defp exact_transaction(_transaction), do: :error

  defp rpc_options(:staking),
    do: [client_key: :staking_http_client, log_scope: "staking transaction"]

  defp rpc_options(:redemption),
    do: [client_key: :redemption_http_client, log_scope: "redemption transaction"]
end
