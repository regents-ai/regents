defmodule AshPlatform.Staking.Actions do
  @moduledoc false

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Staking.ChainClient
  alias AshPlatform.WalletActions.{Abi, Address, Envelope, StakeRedeemOperations}

  @capability :stake
  @rejection_reason "wallet reported an explicit user rejection"
  @withdrawal_reason "review withdrawn"

  # A Base read that may answer differently later. Everything else refuses for
  # good, so only these keep a submitted transaction open for another attempt.
  @transient [:chain_unavailable, :chain_timeout, :invalid_chain_response, :invalid_block_header]
  @resource "regent_staking"
  @contract_name "RegentRevenueStaking"
  @actions ~w(stake unstake claim_usdc claim_regent claim_and_restake_regent)
  @claims ~w(claim_usdc claim_regent claim_and_restake_regent)
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

  # Stake's own lookup: membership is a session fact, not a chain fact, so the
  # reported active wallet is proved against the account the mounted lease
  # resolves to before that wallet's position is read.
  def account_for_wallet(input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- current_wallet(input.arguments.expected_signer, context),
         do: ChainClient.module().overview(signer)
  end

  def account_for_wallet(_input, _context), do: {:error, :authentication_required}

  defp current_wallet(address, context) do
    with {:ok, signer} <- normalize_address(address),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer),
         do: {:ok, signer}
  end

  # The provider reads happen here, before the lease transaction; only the
  # resulting operation row is written inside it.
  def prepare(action, input, %{actor: %Human{}} = context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context),
         :ok <- leased_wallet(lease, signer),
         {:ok, amount} <- requested_amount(action, input.arguments),
         :ok <- within_limits(action, amount, signer),
         {:ok, data, approval, arguments} <- calldata(action, amount, signer),
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
      |> ChainClient.module().confirm(input.arguments.transaction_hash)
      |> transient_refusal()
      |> StakeRedeemOperations.settle_action(lease, @capability, envelope.action_id)
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm(_input, _context), do: {:error, :authentication_required}

  # A read that may answer differently later becomes the typed refusal the page
  # retries; every other refusal is settled and says so instead.
  defp transient_refusal({:error, reason}) when reason in @transient,
    do: refusal(:chain_unavailable)

  defp transient_refusal(result), do: result

  # The reviewed action and the exact current approval are proved here, against
  # the provider, before any transaction opens. The locked account and the stored
  # envelope's signer decide the claim itself, inside it.
  @doc false
  def claim_dispatch(%{arguments: %{envelope: envelope, phase: phase}}, %{actor: %Human{}} = ctx) do
    envelope = atomize_envelope(envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- dispatch_approval(envelope, phase),
         {:ok, lease} <- StakeRedeemOperations.lease(ctx),
         {:ok, operation} <-
           StakeRedeemOperations.claim_dispatch(lease, @capability, envelope.action_id, phase) do
      {:ok, %{operation: StakeRedeemOperations.view(operation)}}
    else
      false -> {:error, :stale_or_invalid_action}
      {:error, reason} -> {:error, reason}
    end
  end

  def claim_dispatch(_input, _context), do: {:error, :authentication_required}

  # The stake spends the approval, so the exact allowance has to be current on a
  # fresh safe snapshot at the moment this dispatch is claimed. If it changed,
  # nothing is claimed and the verified review stays withdrawable.
  defp dispatch_approval(envelope, :action) do
    case ChainClient.module().approval_current(envelope) do
      :ok -> :ok
      {:error, reason} when reason in @transient -> refusal(:chain_unavailable)
      {:error, _changed} -> refusal(:approval_changed)
    end
  end

  defp dispatch_approval(_envelope, :approval), do: :ok

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
  def release_unstarted(%{arguments: %{action_id: id, phase: phase}}, context),
    do: operate(context, &StakeRedeemOperations.release_unstarted(&1, @capability, id, phase))

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

  # The approval's own safe receipt and its own event complete the approval
  # transaction. The mutable allowance is checked later, at the dispatch that
  # spends it, and never here.
  def approval_status(input, %{actor: %Human{} = actor} = context) do
    envelope = atomize_envelope(input.arguments.envelope)

    with true <- valid_for_confirmation?(envelope),
         :ok <- verified_wallet(actor, envelope.expected_signer),
         {:ok, lease} <- StakeRedeemOperations.lease(context) do
      envelope
      |> ChainClient.module().approval_status(input.arguments.transaction_hash)
      |> transient_refusal()
      |> settle_approval(lease, envelope.action_id)
    else
      _ -> {:error, :invalid_submitted_action}
    end
  end

  def approval_status(_input, _context), do: {:error, :authentication_required}

  defp settle_approval({:ok, :pending}, _lease, _action_id), do: {:ok, :pending}

  defp settle_approval({:ok, outcome}, lease, action_id) do
    with {:ok, operation} <-
           StakeRedeemOperations.settle(lease, @capability, action_id, :approval, outcome),
         do: {:ok, approval_state(operation.state)}
  end

  defp settle_approval({:error, reason}, _lease, _action_id), do: {:error, reason}

  defp approval_state(:approval_verified), do: :confirmed
  defp approval_state(terminal), do: terminal

  defp calldata("stake", amount, signer) do
    approval = %{
      token: Abi.normalize_address!(Abi.stake_token_address()),
      spender: Abi.normalize_address!(Abi.staking_address()),
      amount: Integer.to_string(amount),
      data: Abi.encode_erc20("approve", [Abi.staking_address(), amount]),
      mode: "exact"
    }

    {:ok, Abi.encode_action("stake", [amount, signer]), approval,
     %{amount_atomic: Integer.to_string(amount), receiver: signer}}
  end

  defp calldata("unstake", amount, signer),
    do:
      {:ok, Abi.encode_action("unstake", [amount, signer]), nil,
       %{amount_atomic: Integer.to_string(amount), recipient: signer}}

  defp calldata("claim_usdc", _amount, signer),
    do: {:ok, Abi.encode_action("claim_usdc", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_regent", _amount, signer),
    do: {:ok, Abi.encode_action("claim_regent", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_and_restake_regent", _amount, _signer),
    do: {:ok, Abi.encode_action("claim_and_restake_regent", []), nil, %{}}

  defp requested_amount(action, arguments) when action in ["stake", "unstake"],
    do: parse_amount(arguments.amount)

  defp requested_amount(_action, _arguments), do: {:ok, nil}

  @doc """
  The one REGENT amount language: exact decimal digits, at most eighteen places.

  The form validates against this so the page never invites an amount that
  preparation would refuse.
  """
  def parse_amount(value) when is_binary(value) do
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

  def parse_amount(_value), do: {:error, :invalid_amount}

  # Every limit comes from one canonical snapshot, taken here. The contract stays
  # the final authority if that state changes afterwards.
  defp within_limits(action, amount, signer) do
    with {:ok, staking} <- current_position(signer) do
      case limit_refusal(staking, action, amount) do
        nil -> :ok
        reason -> refusal(reason)
      end
    end
  end

  defp current_position(signer) do
    case ChainClient.module().overview(signer) do
      {:ok, staking} -> {:ok, staking}
      {:error, _unavailable} -> refusal(:chain_unavailable)
    end
  end

  @doc """
  The one fact that refuses this action against this snapshot, or `nil`.

  Preparation and the Stake form ask this same question of the same snapshot, so
  the page never invites an amount preparation would refuse. A value that could
  not be read is unavailable evidence, never a balance or a reward of nothing.
  """
  @spec limit_refusal(map(), String.t(), pos_integer() | nil) :: atom() | nil
  def limit_refusal(%{paused: true}, "stake", _amount), do: :staking_paused

  def limit_refusal(staking, "stake", amount) do
    with {:ok, balance} <- atomic(staking.wallet_token_balance_raw),
         {:ok, capacity} <- atomic(staking.remaining_capacity_raw) do
      cond do
        amount > balance -> :amount_above_balance
        amount > capacity -> :amount_above_capacity
        true -> nil
      end
    else
      :error -> :chain_unavailable
    end
  end

  def limit_refusal(staking, "unstake", amount) do
    case atomic(staking.wallet_stake_balance_raw) do
      {:ok, staked} when amount <= staked -> nil
      {:ok, _above} -> :amount_above_stake
      :error -> :chain_unavailable
    end
  end

  def limit_refusal(staking, "claim_usdc", _amount) do
    case atomic(staking.wallet_claimable_usdc_raw) do
      {:ok, claimable} when claimable > 0 -> nil
      {:ok, _nothing} -> :no_claimable_usdc
      :error -> :chain_unavailable
    end
  end

  def limit_refusal(staking, "claim_regent", _amount), do: funded_regent(staking)

  def limit_refusal(staking, "claim_and_restake_regent", _amount) do
    with nil <- funded_regent(staking),
         {:ok, earned} <- atomic(staking.wallet_claimable_regent_raw),
         {:ok, capacity} <- atomic(staking.remaining_capacity_raw) do
      if earned > capacity, do: :amount_above_capacity
    else
      :error -> :chain_unavailable
      refused -> refused
    end
  end

  @doc """
  The claim actions this snapshot permits, by the same rule preparation applies.

  The page offers exactly these, so no control can invite a claim the contract
  or the reward inventory would refuse a moment later.
  """
  @spec available_claims(map() | nil) :: [String.t()]
  def available_claims(nil), do: []

  def available_claims(staking),
    do: Enum.filter(@claims, &is_nil(limit_refusal(staking, &1, nil)))

  @doc """
  The exact raw amount this action may spend on this snapshot, or zero.

  A stake is bounded by the wallet and by what the contract can still take, so
  neither `50%` nor `Max` can name more REGENT than may actually be staked.
  """
  @spec spendable(map() | nil, String.t()) :: non_neg_integer()
  def spendable(%{wallet_token_balance_raw: wallet, remaining_capacity_raw: capacity}, "stake"),
    do: min(available(wallet), available(capacity))

  def spendable(%{wallet_stake_balance_raw: staked}, "unstake"), do: available(staked)
  def spendable(_unread, _action), do: 0

  defp funded_regent(staking) do
    with {:ok, earned} <- atomic(staking.wallet_claimable_regent_raw),
         {:ok, funded} <- atomic(staking.wallet_funded_claimable_regent_raw) do
      if earned > 0 and funded >= earned, do: nil, else: :regent_rewards_not_funded
    else
      :error -> :chain_unavailable
    end
  end

  defp atomic(value) do
    case Integer.parse(value || "") do
      {amount, ""} -> {:ok, amount}
      _unavailable -> :error
    end
  end

  defp available(value) do
    case atomic(value) do
      {:ok, amount} -> amount
      :error -> 0
    end
  end

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
  # reviewed wallet has to belong to. The two refusals are typed and distinct: a
  # session that no longer resolves an account has said nothing at all about
  # whose wallet this is, and only a resolved account can call one an outsider.
  defp leased_wallet(%{lineage: lineage, account_id: account_id}, signer),
    do: lineage |> SessionAuthority.leased_account(account_id) |> wallet_member(signer)

  defp wallet_member(nil, _signer), do: refusal(:session_unavailable)

  defp wallet_member(%{wallet_addresses: wallets}, signer) do
    if Enum.any?(wallets || [], &Address.equal?(&1, signer)),
      do: :ok,
      else: refusal(:wrong_signer)
  end

  defp verified_wallet(%Human{} = actor, signer) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         wallets when is_list(wallets) <- account.wallet_addresses,
         true <- Enum.any?(wallets, &Address.equal?(&1, signer)) do
      :ok
    else
      _ -> {:error, :wrong_signer}
    end
  end

  defp primary_wallet(%{wallet_address: address}) do
    case Address.normalize(address) do
      {:ok, wallet} -> {:ok, wallet}
      :error -> {:error, :wallet_required}
    end
  end

  defp normalize_address(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:ok, address}
      :error -> {:error, :invalid_wallet}
    end
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
