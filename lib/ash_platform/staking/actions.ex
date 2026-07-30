defmodule AshPlatform.Staking.Actions do
  @moduledoc false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.Human
  alias AshPlatform.Staking.ChainClient
  alias AshPlatform.WalletActions.{Abi, Envelope}

  @resource "regent_staking"
  @contract_name "RegentRevenueStaking"
  @actions ~w(stake unstake claim_usdc claim_regent claim_and_restake_regent)
  @risk %{
    "stake" =>
      "Stake REGENT from your connected wallet. This may require a separate exact token approval before staking.",
    "unstake" => "Return the selected amount of staked REGENT to your connected wallet.",
    "claim_usdc" =>
      "Claim all currently available USDC staking rewards to your connected wallet.",
    "claim_regent" => "Claim all currently available REGENT rewards to your connected wallet.",
    "claim_and_restake_regent" =>
      "Claim available REGENT rewards and add them to your stake. This happens only when you choose this action."
  }

  def overview(_input, _context), do: ChainClient.module().overview(nil)

  def account(_input, %{actor: %Human{} = actor}) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         {:ok, wallet} <- primary_wallet(account) do
      ChainClient.module().overview(wallet)
    end
  end

  def account(_input, _context), do: {:error, :authentication_required}

  def prepare(action, input, %{actor: %Human{} = actor}) do
    signer = input.arguments.expected_signer

    with {:ok, signer} <- normalize_address(signer),
         :ok <- verified_wallet(actor, signer),
         :ok <- ensure_funded(action, signer),
         {:ok, data, approval, arguments} <- calldata(action, input.arguments, signer) do
      {:ok,
       Envelope.new(action, signer, data,
         to: Abi.staking_address(),
         resource: @resource,
         contract_name: @contract_name,
         risk_copy: Map.fetch!(@risk, action),
         approval: approval,
         arguments: arguments
       )}
    end
  end

  def prepare(_action, _input, _context), do: {:error, :authentication_required}

  def confirm(input, %{actor: %Human{} = actor}) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      case ChainClient.module().confirm(
             envelope,
             input.arguments.transaction_hash,
             input.arguments.approval_transaction_hash
           ) do
        {:ok, result} ->
          {:ok, result}

        {:error, :transaction_reverted} ->
          {:ok,
           %{
             transaction_hash: input.arguments.transaction_hash,
             receipt_verified: true,
             transaction_reverted: true,
             staking: nil
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm(_input, _context), do: {:error, :authentication_required}

  def restore(input, %{actor: %Human{} = actor}) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      {:ok, envelope}
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def restore(_input, _context), do: {:error, :authentication_required}

  def approval_status(input, %{actor: %Human{} = actor}) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer) do
      ChainClient.module().approval_status(envelope, input.arguments.transaction_hash)
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def approval_status(_input, _context), do: {:error, :authentication_required}

  defp calldata("stake", arguments, signer) do
    with {:ok, amount} <- parse_amount(arguments.amount) do
      approval_data = Abi.encode_erc20("approve", [Abi.staking_address(), amount])

      approval = %{
        token: Abi.normalize_address!(Abi.stake_token_address()),
        spender: Abi.normalize_address!(Abi.staking_address()),
        amount: Integer.to_string(amount),
        data: approval_data,
        mode: "exact"
      }

      {:ok, Abi.encode_action("stake", [amount, signer]), approval,
       %{amount_atomic: Integer.to_string(amount), receiver: signer}}
    end
  end

  defp calldata("unstake", arguments, signer) do
    with {:ok, amount} <- parse_amount(arguments.amount) do
      {:ok, Abi.encode_action("unstake", [amount, signer]), nil,
       %{amount_atomic: Integer.to_string(amount), recipient: signer}}
    end
  end

  defp calldata("claim_usdc", _arguments, signer),
    do: {:ok, Abi.encode_action("claim_usdc", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_regent", _arguments, signer),
    do: {:ok, Abi.encode_action("claim_regent", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_and_restake_regent", _arguments, _signer),
    do: {:ok, Abi.encode_action("claim_and_restake_regent", []), nil, %{}}

  defp parse_amount(value) when is_binary(value) do
    value = String.trim(value)

    with true <- String.match?(value, ~r/^\d+(?:\.\d{1,18})?$/),
         {decimal, ""} <- Decimal.parse(value),
         :gt <- Decimal.compare(decimal, 0),
         scaled <- Decimal.mult(decimal, Decimal.new(Integer.pow(10, 18))),
         rounded <- Decimal.round(scaled, 0),
         :eq <- Decimal.compare(scaled, rounded) do
      {:ok, Decimal.to_integer(rounded)}
    else
      _ -> {:error, :invalid_amount}
    end
  end

  defp parse_amount(_value), do: {:error, :invalid_amount}

  defp ensure_funded(action, signer)
       when action in ["claim_regent", "claim_and_restake_regent"] do
    with {:ok, staking} <- ChainClient.module().overview(signer),
         {earned, ""} <- Integer.parse(staking.wallet_claimable_regent_raw || "0"),
         {funded, ""} <- Integer.parse(staking.wallet_funded_claimable_regent_raw || "0"),
         true <- earned > 0 and funded >= earned do
      :ok
    else
      _ -> {:error, :regent_rewards_not_funded}
    end
  end

  defp ensure_funded(_action, _signer), do: :ok

  defp verified_wallet(%Human{} = actor, signer) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallets when is_list(wallets) <- account.wallet_addresses,
         true <- Enum.any?(wallets, &(normalize_or_nil(&1) == signer)) do
      :ok
    else
      _ -> {:error, :wrong_signer}
    end
  end

  defp primary_wallet(account) do
    case normalize_or_nil(account.wallet_address) do
      nil -> {:error, :wallet_required}
      wallet -> {:ok, wallet}
    end
  end

  defp normalize_address(value) do
    {:ok, Abi.normalize_address!(value)}
  rescue
    _ -> {:error, :invalid_wallet}
  end

  defp normalize_or_nil(value) do
    Abi.normalize_address!(value)
  rescue
    _ -> nil
  end

  defp valid_for_confirmation?(envelope) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      to: Abi.staking_address(),
      signer: envelope.expected_signer,
      contract_name: @contract_name,
      actions: @actions
    )
  end

  defp atomize_envelope(envelope) when is_map(envelope) do
    %{
      action_id: field(envelope, :action_id),
      idempotency_key: field(envelope, :idempotency_key),
      resource: field(envelope, :resource),
      action: field(envelope, :action),
      chain_id: field(envelope, :chain_id),
      to: field(envelope, :to),
      value: field(envelope, :value),
      data: field(envelope, :data),
      expected_signer: field(envelope, :expected_signer),
      prepared_at: field(envelope, :prepared_at),
      expires_at: field(envelope, :expires_at),
      risk_copy: field(envelope, :risk_copy),
      approval: field(envelope, :approval),
      arguments: field(envelope, :arguments),
      metadata: field(envelope, :metadata),
      confirmation_token: field(envelope, :confirmation_token)
    }
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
