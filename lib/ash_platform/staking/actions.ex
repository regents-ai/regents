defmodule AshPlatform.Staking.Actions do
  @moduledoc false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Staking.ChainClient
  alias AshPlatform.WalletActions.{Abi, Envelope, StakeRedeemOperations}

  @capability :stake
  @rejection_reason "wallet reported an explicit user rejection"
  @withdrawal_reason "review withdrawn"
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

  # Stake's own lookup: the reviewed active wallet, proven against the account
  # the mounted lease still resolves to, decides which position is read.
  def account_for_wallet(input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer) do
      ChainClient.module().overview(signer)
    end
  end

  def account_for_wallet(_input, _context), do: {:error, :authentication_required}

  # The provider reads happen here, before the lease transaction; only the
  # resulting operation row is written inside it.
  def prepare(action, input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer),
         :ok <- ensure_funded(action, signer),
         {:ok, data, approval, arguments} <- calldata(action, input.arguments, signer),
         envelope <-
           Envelope.new(action, signer, data,
             to: Abi.staking_address(),
             resource: @resource,
             contract_name: @contract_name,
             risk_copy: Map.fetch!(@risk, action),
             approval: approval,
             arguments: arguments
           ),
         {:ok, _operation} <- StakeRedeemOperations.prepare(lease, @capability, envelope) do
      {:ok, envelope}
    end
  end

  def prepare(_action, _input, _context), do: {:error, :authentication_required}

  def confirm(input, %{actor: %Human{} = actor} = context) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         # Confirmation and every retry run against the stored submitted
         # identity: an exact replay passes, a different hash is refused.
         {:ok, _identity} <-
           StakeRedeemOperations.bind_hash(
             lease,
             @capability,
             envelope.action_id,
             :action,
             input.arguments.transaction_hash
           ) do
      envelope
      |> ChainClient.module().confirm(
        input.arguments.transaction_hash,
        input.arguments.approval_transaction_hash
      )
      |> record_action_outcome(lease, envelope, input.arguments.transaction_hash)
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm(_input, _context), do: {:error, :authentication_required}

  # Receipt and reread are recorded as they become known. Only their agreement
  # reaches the terminal `:confirmed` state.
  defp record_action_outcome({:ok, %{reread_verified: true} = result}, lease, envelope, _hash) do
    with {:ok, _receipt} <- record_receipt(lease, envelope, :action),
         {:ok, _confirmed} <-
           StakeRedeemOperations.confirm(lease, @capability, envelope.action_id) do
      {:ok, result}
    end
  end

  defp record_action_outcome({:ok, result}, lease, envelope, _hash) do
    with {:ok, _receipt} <- record_receipt(lease, envelope, :action), do: {:ok, result}
  end

  defp record_action_outcome({:error, :transaction_reverted}, lease, envelope, hash) do
    with {:ok, _reverted} <-
           StakeRedeemOperations.record_revert(
             lease,
             @capability,
             envelope.action_id,
             :action,
             "verified revert on Base"
           ) do
      {:ok,
       %{
         transaction_hash: hash,
         receipt_verified: true,
         transaction_reverted: true,
         reread_verified: false,
         staking: nil
       }}
    end
  end

  defp record_action_outcome({:error, reason}, _lease, _envelope, _hash), do: {:error, reason}

  defp record_receipt(lease, envelope, phase),
    do: StakeRedeemOperations.record_receipt(lease, @capability, envelope.action_id, phase)

  @doc false
  def claim_dispatch(%{arguments: %{action_id: id, phase: phase}}, context),
    do: operate(context, &StakeRedeemOperations.claim_dispatch(&1, @capability, id, phase))

  @doc false
  def bind_hash(%{arguments: %{action_id: id, phase: phase, transaction_hash: hash}}, context),
    do: operate(context, &StakeRedeemOperations.bind_hash(&1, @capability, id, phase, hash))

  @doc false
  def close_not_sent(%{arguments: %{action_id: id, phase: phase}}, context),
    do:
      operate(
        context,
        &StakeRedeemOperations.close_not_sent(&1, @capability, id, phase, @rejection_reason)
      )

  @doc false
  def cancel_operation(%{arguments: %{action_id: id}}, context),
    do: operate(context, &StakeRedeemOperations.cancel(&1, @capability, id, @withdrawal_reason))

  @doc false
  def active_operation(_input, %{actor: %Human{} = actor}) do
    with {:ok, operation} <- StakeRedeemOperations.active(actor.human_account_id, @capability),
         do: {:ok, %{operation: StakeRedeemOperations.view(operation)}}
  end

  def active_operation(_input, _context), do: {:error, :authentication_required}

  defp operate(%{actor: %Human{}} = context, transition) do
    with {:ok, lease} <- StakeRedeemOperations.lease(context),
         {:ok, operation} <- transition.(lease) do
      {:ok, %{operation: StakeRedeemOperations.view(operation)}}
    end
  end

  defp operate(_context, _transition), do: {:error, :authentication_required}

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

  def approval_status(input, %{actor: %Human{} = actor} = context) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         {:ok, status} <-
           ChainClient.module().approval_status(envelope, input.arguments.transaction_hash) do
      record_approval_outcome(status, lease, envelope)
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def approval_status(_input, _context), do: {:error, :authentication_required}

  # `:success` already means receipt plus the exact allowance, so it is the only
  # status that may complete the approval phase.
  defp record_approval_outcome(:success, lease, envelope) do
    with {:ok, _receipt} <- record_receipt(lease, envelope, :approval),
         {:ok, _verified} <-
           StakeRedeemOperations.verify_approval(lease, @capability, envelope.action_id) do
      {:ok, :success}
    end
  end

  defp record_approval_outcome(:reverted, lease, envelope) do
    with {:ok, _reverted} <-
           StakeRedeemOperations.record_revert(
             lease,
             @capability,
             envelope.action_id,
             :approval,
             "verified approval revert on Base"
           ) do
      {:ok, :reverted}
    end
  end

  defp record_approval_outcome(status, _lease, _envelope), do: {:ok, status}

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
      _ -> refusal(:regent_rewards_not_funded)
    end
  end

  # A claim of nothing is refused on current chain truth rather than on the
  # screen's copy of it. An unavailable provider read is unavailable, not zero.
  defp ensure_funded("claim_usdc", signer) do
    with {:ok, staking} <- ChainClient.module().overview(signer),
         {claimable, ""} <- Integer.parse(staking.wallet_claimable_usdc_raw || "0"),
         true <- claimable > 0 do
      :ok
    else
      _ -> refusal(:no_claimable_usdc)
    end
  end

  defp ensure_funded(_action, _signer), do: :ok

  # A typed Ash error, so the refusal survives the action's error class and the
  # presenter can name the fact that actually stopped the review.
  defp refusal(reason),
    do:
      {:error,
       Ash.Error.Invalid.Unavailable.exception(
         resource: AshPlatform.Staking.Snapshot,
         reason: reason
       )}

  # The lease, not the actor captured at mount, decides which account the
  # reviewed wallet has to belong to before any provider read happens. The
  # refusal is typed, so the page can tell a wallet that does not belong to this
  # account from a chain read that was merely unavailable.
  defp leased_wallet(%{lineage: lineage, account_id: account_id}, signer) do
    with %{wallet_addresses: wallets} <- SessionAuthority.leased_account(lineage, account_id),
         true <- Enum.any?(wallets || [], &(normalize_or_nil(&1) == signer)) do
      :ok
    else
      _ -> refusal(:wrong_signer)
    end
  end

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
