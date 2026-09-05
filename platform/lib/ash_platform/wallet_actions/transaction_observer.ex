defmodule AshPlatform.WalletActions.TransactionObserver do
  @moduledoc false

  alias AshPlatform.WalletActions.Rpc

  @callback observe(map(), :staking | :redemption) ::
              :success | :reverted | :delayed | :unavailable

  # Base confirms a block about every two seconds, so one poll per block for a
  # minute covers an ordinary confirmation many times over.
  @delays [0] ++ List.duplicate(2_000, 30)

  @doc false
  def delays, do: @delays

  def observe(transaction, scope) when scope in [:staking, :redemption] do
    module = Application.get_env(:ash_platform, :wallet_transaction_observer, __MODULE__)

    if module == __MODULE__,
      do: observe_rpc(transaction, scope, @delays),
      else: module.observe(transaction, scope)
  end

  @doc false
  def observe_rpc(transaction, scope, delays) when scope in [:staking, :redemption] do
    case exact_transaction(transaction) do
      {:ok, exact} -> poll(exact, rpc_options(scope), delays, :delayed)
      :error -> :unavailable
    end
  end

  # An exhausted schedule reports the last thing Base actually said about this
  # transaction: still unconfirmed, or unreadable.
  defp poll(_transaction, _opts, [], unresolved), do: unresolved

  defp poll(transaction, opts, [delay | remaining], _unresolved) do
    if delay > 0, do: Process.sleep(delay)

    with {:ok, block} <- Rpc.latest_block(opts),
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
        :pending -> poll(transaction, opts, remaining, :delayed)
        :reverted -> :reverted
        {:success, _logs} -> :success
      end
    else
      # A read that did not happen is worth repeating: at the chain head a node
      # may time out or refuse mid-schedule, which says nothing about this
      # transaction. Only an exhausted schedule reports it, and it can never
      # become a success — only a canonical receipt does that.
      {:error, :chain_unavailable} ->
        poll(transaction, opts, remaining, :unavailable)

      # Every other reason is a decided answer about this provider, this
      # receipt, or this transaction. Repeating the read would return it again,
      # so it is reported at once.
      {:error, _decided} ->
        :unavailable
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
