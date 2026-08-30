defmodule AshPlatform.Staking.Actions do
  @moduledoc false
  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human
  alias AshPlatform.Staking.ChainClient
  alias AshPlatform.WalletActions.{Abi, Address, Envelope}

  @resource "regent_staking"
  @contract_name "RegentRevenueStaking"
  @actions ~w(stake unstake claim_usdc claim_regent claim_and_restake_regent)
  @claims ~w(claim_usdc claim_regent claim_and_restake_regent)
  @risk %{
    "stake" => "Stake REGENT from your connected wallet.",
    "unstake" => "Return the selected amount of staked REGENT to your connected wallet.",
    "claim_usdc" => "Claim all currently available USDC staking rewards.",
    "claim_regent" => "Claim all currently available REGENT rewards.",
    "claim_and_restake_regent" => "Claim available REGENT rewards and add them to your stake."
  }

  def overview(_input, _context), do: ChainClient.module().overview(nil)

  def account(_input, %{actor: %Human{} = actor}) do
    with {:ok, account} <- Accounts.get_human_account(actor.human_account_id, actor: actor),
         {:ok, wallet} <- normalize_address(account.wallet_address),
         do: ChainClient.module().overview(wallet)
  end

  def account(_input, _context), do: {:error, :authentication_required}

  def account_for_wallet(input, %{actor: %Human{}} = context) do
    with {:ok, signer, _lease} <- current_wallet(input.arguments.expected_signer, context),
         do: ChainClient.module().overview(signer)
  end

  def account_for_wallet(_input, _context), do: {:error, :authentication_required}

  def prepare(action, input, %{actor: %Human{}} = context) do
    with {:ok, signer, lease} <- current_wallet(input.arguments.expected_signer, context),
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
           ) do
      return_current(lease, signer, envelope)
    end
  end

  def prepare(_action, _input, _context), do: {:error, :authentication_required}

  defp current_wallet(address, context) do
    with {:ok, signer} <- normalize_address(address),
         {:ok, lease} <- lease(context),
         account when not is_nil(account) <-
           SessionAuthority.leased_account(lease.lineage, lease.account_id),
         :ok <- wallet_member(account, signer),
         do: {:ok, signer, lease}
  end

  defp return_current(lease, signer, envelope) do
    callback = fn account -> current_envelope(account, signer, envelope) end

    case SessionAuthority.transact_lease(lease.lineage, lease.account_id, callback) do
      {:error, :stale_authority} -> refusal(:session_unavailable)
      false -> refusal(:stale_or_invalid_action)
      result -> result
    end
  end

  defp current_envelope(account, signer, envelope) do
    with :ok <- wallet_member(account, signer),
         true <- valid_envelope?(envelope),
         do: {:ok, envelope}
  end

  defp valid_envelope?(envelope),
    do:
      Envelope.valid_for_confirmation?(envelope,
        resource: @resource,
        to: Abi.staking_address(),
        signer: envelope.expected_signer,
        contract_name: @contract_name,
        actions: @actions
      )

  defp calldata("stake", amount, signer) do
    approval = %{
      token: Abi.normalize_address!(Abi.stake_token_address()),
      spender: Abi.normalize_address!(Abi.staking_address()),
      amount: Integer.to_string(amount),
      data: Abi.encode_erc20("approve", [Abi.staking_address(), amount]),
      mode: "exact"
    }

    with {:ok, allowance} <- ChainClient.module().allowance(signer, amount) do
      {:ok, Abi.encode_action("stake", [amount, signer]),
       if(allowance == :sufficient, do: nil, else: approval),
       %{amount_atomic: Integer.to_string(amount), receiver: signer}}
    end
  end

  defp calldata("unstake", amount, signer),
    do:
      {:ok, Abi.encode_action("unstake", [amount, signer]), nil,
       %{amount_atomic: Integer.to_string(amount), recipient: signer}}

  defp calldata("claim_usdc", _, signer),
    do: {:ok, Abi.encode_action("claim_usdc", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_regent", _, signer),
    do: {:ok, Abi.encode_action("claim_regent", [signer]), nil, %{recipient: signer}}

  defp calldata("claim_and_restake_regent", _, _),
    do: {:ok, Abi.encode_action("claim_and_restake_regent", []), nil, %{}}

  defp calldata(_, _, _), do: {:error, :unknown_action}

  defp requested_amount(action, arguments) when action in ["stake", "unstake"],
    do: parse_amount(arguments.amount)

  defp requested_amount(_, _), do: {:ok, nil}

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

  def parse_amount(_), do: {:error, :invalid_amount}

  defp within_limits(action, amount, signer) do
    case ChainClient.module().overview(signer) do
      {:ok, staking} ->
        case limit_refusal(staking, action, amount) do
          nil -> :ok
          reason -> refusal(reason)
        end

      _ ->
        refusal(:chain_unavailable)
    end
  end

  def limit_refusal(%{paused: true}, "stake", _), do: :staking_paused

  def limit_refusal(%{paused: true}, "claim_and_restake_regent", _),
    do: :staking_paused

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
      {:ok, _} -> :amount_above_stake
      :error -> :chain_unavailable
    end
  end

  def limit_refusal(staking, "claim_usdc", _) do
    case atomic(staking.wallet_claimable_usdc_raw) do
      {:ok, value} when value > 0 -> nil
      {:ok, _} -> :no_claimable_usdc
      :error -> :chain_unavailable
    end
  end

  def limit_refusal(staking, "claim_regent", _), do: funded_regent(staking)

  def limit_refusal(staking, "claim_and_restake_regent", _) do
    with nil <- funded_regent(staking),
         {:ok, earned} <- atomic(staking.wallet_claimable_regent_raw),
         {:ok, capacity} <- atomic(staking.remaining_capacity_raw) do
      if earned > capacity, do: :amount_above_capacity
    else
      :error -> :chain_unavailable
      refused -> refused
    end
  end

  def available_claims(nil), do: []

  def available_claims(staking),
    do: Enum.filter(@claims, &is_nil(limit_refusal(staking, &1, nil)))

  def spendable(%{wallet_token_balance_raw: wallet, remaining_capacity_raw: capacity}, "stake"),
    do: min(available(wallet), available(capacity))

  def spendable(%{wallet_stake_balance_raw: staked}, "unstake"), do: available(staked)
  def spendable(_, _), do: 0

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
      _ -> :error
    end
  end

  defp available(value) do
    case atomic(value) do
      {:ok, amount} -> amount
      :error -> 0
    end
  end

  defp lease(%{source_context: %{session_lease: %{lineage: lineage, account_id: account_id}}})
       when is_binary(lineage) and is_integer(account_id),
       do: {:ok, %{lineage: lineage, account_id: account_id}}

  defp lease(_), do: {:error, :session_lease_required}

  defp wallet_member(%{wallet_addresses: wallets}, signer),
    do:
      if(Enum.any?(wallets || [], &Address.equal?(&1, signer)),
        do: :ok,
        else: refusal(:wrong_signer)
      )

  defp normalize_address(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:ok, address}
      :error -> {:error, :invalid_wallet}
    end
  end

  defp refusal(reason),
    do:
      {:error,
       Ash.Error.Invalid.Unavailable.exception(
         resource: AshPlatform.Staking.Snapshot,
         reason: reason
       )}
end
