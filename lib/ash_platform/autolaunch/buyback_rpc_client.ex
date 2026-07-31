defmodule AshPlatform.Autolaunch.BuybackRpcClient do
  @moduledoc false
  @behaviour AshPlatform.Autolaunch.BuybackChainClient

  alias AshPlatform.WalletActions.{Envelope, Rpc}

  @resource "autolaunch_buyback"
  @contract_name "RegentStakingRevenueRouter"
  @action "settle_treasury_buyback"
  @rpc_opts [client_key: :autolaunch_buyback_http_client, log_scope: "autolaunch buyback"]

  @impl true
  def confirm(envelope, transaction_hash) do
    with true <- valid_for_confirmation?(envelope),
         true <- is_nil(envelope.approval),
         true <- Rpc.valid_hash?(transaction_hash),
         :ok <- Rpc.verify_base_chain(@rpc_opts),
         :ok <-
           Rpc.confirmed_transaction(
             transaction_hash,
             envelope.expected_signer,
             envelope.to,
             envelope.data,
             @rpc_opts
           ) do
      {:ok,
       %{
         transaction_hash: String.downcase(transaction_hash),
         receipt_verified: true
       }}
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_for_confirmation?(envelope) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      to: envelope.to,
      signer: envelope.expected_signer,
      contract_name: @contract_name,
      action: @action
    )
  end
end
