defmodule AshPlatform.Autolaunch.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Autolaunch.ChainClient

  alias AshPlatform.WalletActions.{Envelope, Rpc}

  @auction_resource "autolaunch_auction"
  @bid_resource "autolaunch_bid"
  @contract_name "IContinuousClearingAuction"
  @actions ~w(submit_bid exit_bid return_quote_token claim_bid)
  @rpc_opts [client_key: :autolaunch_bid_http_client, log_scope: "autolaunch bid"]

  @impl true
  def confirm(envelope, transaction_hash, approval_transaction_hash) do
    with true <- valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(transaction_hash),
         :ok <- Rpc.verify_base_chain(@rpc_opts),
         :ok <- verify_approval(envelope, approval_transaction_hash),
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

  @impl true
  def approval_status(%{approval: approval, expected_signer: signer} = envelope, hash)
      when is_map(approval) do
    with true <- valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(hash),
         :ok <- Rpc.verify_base_chain(@rpc_opts) do
      Rpc.submission_status(
        hash,
        signer,
        field(approval, :token),
        field(approval, :data),
        @rpc_opts
      )
    else
      false -> {:error, :invalid_approval_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  def approval_status(_envelope, _hash), do: {:error, :invalid_approval_confirmation}

  defp verify_approval(%{approval: nil}, nil), do: :ok
  defp verify_approval(%{approval: nil}, _hash), do: {:error, :unexpected_approval}
  defp verify_approval(%{approval: _approval}, nil), do: {:error, :approval_required}

  defp verify_approval(%{approval: approval, expected_signer: signer}, hash) do
    with true <- Rpc.valid_hash?(hash),
         :ok <-
           Rpc.confirmed_transaction(
             hash,
             signer,
             field(approval, :token),
             field(approval, :data),
             @rpc_opts
           ) do
      :ok
    else
      false -> {:error, :invalid_approval_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_for_confirmation?(envelope) do
    Envelope.valid_for_confirmation?(envelope,
      resource: envelope.resource,
      to: envelope.to,
      signer: envelope.expected_signer,
      contract_name: @contract_name,
      actions: @actions
    ) and envelope.resource in [@auction_resource, @bid_resource]
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
