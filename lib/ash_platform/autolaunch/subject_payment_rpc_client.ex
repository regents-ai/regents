defmodule AshPlatform.Autolaunch.SubjectPaymentRpcClient do
  @moduledoc false
  @behaviour AshPlatform.Autolaunch.SubjectPaymentChainClient

  alias AshPlatform.WalletActions.{Envelope, Rpc, SubjectPaymentAbi}

  @resources ~w(autolaunch_payment_link autolaunch_ingress autolaunch_subject_staking)
  @contract_names ~w(PaymentLinkFactory RevenueIngressAccount RevenueShareSplitterV2)
  @actions ~w(
    create_payment_link
    create_canonical_payment_link
    set_payment_link_canonical
    set_payment_link_receiver_state
    sweep_usdc
    stake
    unstake
    claim_usdc
  )
  @rpc_opts [
    client_key: :autolaunch_subject_payment_http_client,
    log_scope: "autolaunch subject payment"
  ]

  @impl true
  def confirm(envelope, transaction_hash, approval_transaction_hash) do
    with true <- valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(transaction_hash),
         :ok <- verify_approval(envelope, approval_transaction_hash),
         {:ok, receipt} <-
           Rpc.confirmed_transaction_receipt(
             transaction_hash,
             envelope.expected_signer,
             envelope.to,
             envelope.data,
             @rpc_opts
           ),
         {:ok, result} <- confirmation_result(envelope, receipt, transaction_hash) do
      {:ok, result}
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

  defp confirmation_result(
         %{action: action} = envelope,
         receipt,
         transaction_hash
       )
       when action in ~w(create_payment_link create_canonical_payment_link) do
    subject_id = field(envelope.arguments, :subject_id)

    receiver = payment_link_receiver(receipt["logs"], envelope.to, subject_id)

    if receiver do
      {:ok,
       %{
         transaction_hash: String.downcase(transaction_hash),
         receipt_verified: true,
         payment_link_receiver: receiver
       }}
    else
      {:error, :payment_link_created_event_missing}
    end
  end

  defp confirmation_result(_envelope, _receipt, transaction_hash) do
    {:ok,
     %{
       transaction_hash: String.downcase(transaction_hash),
       receipt_verified: true
     }}
  end

  defp payment_link_receiver(logs, factory, subject_id) when is_list(logs) do
    Enum.find_value(logs, fn log ->
      case SubjectPaymentAbi.payment_link_created_receiver(log, factory, subject_id) do
        {:ok, receiver} -> receiver
        :error -> nil
      end
    end)
  end

  defp payment_link_receiver(_logs, _factory, _subject_id), do: nil

  defp valid_for_confirmation?(envelope) do
    contract_name = field(envelope.metadata, :contract_name)

    Envelope.valid_for_confirmation?(envelope,
      resource: envelope.resource,
      to: envelope.to,
      signer: envelope.expected_signer,
      contract_name: contract_name,
      actions: @actions
    ) and envelope.resource in @resources and contract_name in @contract_names
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
