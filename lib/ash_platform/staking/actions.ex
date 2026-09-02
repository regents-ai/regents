defmodule AshPlatform.Staking.Actions do
  @moduledoc false
  alias AshPlatform.Accounts
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

  def account_for_wallet(input, _context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         do: ChainClient.module().overview(signer)
  end

  def prepare(action, input, _context) do
    with {:ok, signer} <- normalize_address(input.arguments.expected_signer),
         {:ok, amount} <- requested_amount(action, input.arguments),
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
         true <- valid_envelope?(envelope) do
      {:ok, envelope}
    else
      false -> refusal(:stale_or_invalid_action)
      error -> error
    end
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

  @doc """
  What the last Base reading says about each claim, keyed by action.

  A reason here is hint copy and nothing else: every claim control stays
  clickable, the click prepares exact calldata, and the contract decides the
  outcome. `nil` means the reading had nothing to say about that claim.
  """
  def available_claims(nil), do: Map.new(@claims, &{&1, :chain_unavailable})

  def available_claims(staking),
    do: Map.new(@claims, &{&1, limit_refusal(staking, &1, nil)})

  def spendable(%{wallet_token_balance_raw: wallet, remaining_capacity_raw: capacity}, "stake"),
    do: min(available(wallet), available(capacity))

  def spendable(%{wallet_stake_balance_raw: staked}, "unstake"), do: available(staked)
  def spendable(_, _), do: 0

  # Nothing earned and an inventory too small to cover what was earned are
  # different facts, and the page says which one the reading found.
  defp funded_regent(staking) do
    with {:ok, earned} <- atomic(staking.wallet_claimable_regent_raw),
         {:ok, funded} <- atomic(staking.wallet_funded_claimable_regent_raw) do
      cond do
        earned == 0 -> :no_regent_rewards
        funded < earned -> :regent_rewards_not_funded
        true -> nil
      end
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
