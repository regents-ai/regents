defmodule AshPlatform.TestStakingChainClient do
  @behaviour AshPlatform.Staking.ChainClient

  @balances %{
    token: "10000000000000000000",
    stake: "5000000000000000000",
    usdc_wallet: "4250000",
    usdc_claimable: "1500000",
    regent_claimable: "2000000000000000000",
    regent_funded: "2000000000000000000"
  }

  # The deployed cap, so a proof can name an amount the contract could not take.
  @denominator "1000000000000000000000"
  @total_staked "100000000000000000000"

  # An unavailable Base read is its own outcome: it is never a zero balance and
  # never evidence about which wallet is asking.
  @impl true
  def overview(wallet) do
    report_read(Application.get_env(:ash_platform, :test_staking_read_watcher))

    case Application.get_env(:ash_platform, :test_staking_overview_error) do
      nil -> {:ok, snapshot(wallet)}
      reason -> {:error, reason}
    end
  end

  # A test may watch the process doing a position read, so an ordering proof can
  # wait for that read to finish rather than for a duration.
  defp report_read(nil), do: :ok
  defp report_read(test), do: send(test, {:staking_read, self()})

  defp snapshot(wallet) do
    total = String.to_integer(@total_staked)
    denominator = String.to_integer(setting(:test_staking_denominator, @denominator))
    capacity = max(denominator - total, 0)

    %{
      chain_id: 8453,
      chain_label: "Base",
      block_number: 1_234,
      block_hash: "0x" <> String.duplicate("1b", 32),
      contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
      stake_token_address: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
      usdc_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      paused: Application.get_env(:ash_platform, :test_staking_paused, false),
      total_staked_raw: @total_staked,
      total_staked: scaled(@total_staked, 18),
      supply_denominator_raw: Integer.to_string(denominator),
      remaining_capacity_raw: Integer.to_string(capacity),
      remaining_capacity: scaled(Integer.to_string(capacity), 18),
      wallet_address: wallet,
      wallet_token_balance_raw: raw(wallet, :token),
      wallet_token_balance: regent(wallet, :token),
      wallet_usdc_balance_raw: raw(wallet, :usdc_wallet),
      wallet_usdc_balance: usdc(wallet, :usdc_wallet),
      wallet_stake_balance_raw: raw(wallet, :stake),
      wallet_stake_balance: regent(wallet, :stake),
      wallet_claimable_usdc_raw: raw(wallet, :usdc_claimable),
      wallet_claimable_usdc: usdc(wallet, :usdc_claimable),
      wallet_claimable_regent_raw: raw(wallet, :regent_claimable),
      wallet_claimable_regent: regent(wallet, :regent_claimable),
      wallet_funded_claimable_regent_raw: raw(wallet, :regent_funded),
      wallet_funded_claimable_regent: regent(wallet, :regent_funded)
    }
  end

  # The four closed outcomes, chosen by the test rather than by a real receipt.
  @impl true
  def confirm(_envelope, "0x" <> hash = transaction_hash) when byte_size(hash) == 64 do
    await_release(Application.get_env(:ash_platform, :test_staking_confirm_barrier))

    outcome = Application.get_env(:ash_platform, :test_staking_confirmation_result, :confirmed)

    {:ok, %{transaction_hash: transaction_hash, outcome: outcome, reason: nil}}
  end

  def confirm(_envelope, _transaction_hash), do: {:error, :invalid_confirmation}

  # A test may hold a confirmation open here to prove exactly what a result
  # arriving after a wallet change may and may not do to the page.
  defp await_release(nil), do: :ok

  defp await_release(test) do
    send(test, {:staking_confirming, self()})

    receive do
      :release_staking_confirmation -> :ok
    after
      5_000 -> :ok
    end
  end

  @impl true
  def approval_status(_envelope, _transaction_hash),
    do: {:ok, Application.get_env(:ash_platform, :test_staking_approval_status, :confirmed)}

  # The exact allowance read fresh immediately before the stake is dispatched.
  @impl true
  def approval_current(%{approval: nil}), do: :ok

  def approval_current(_envelope) do
    case Application.get_env(:ash_platform, :test_staking_allowance_current, true) do
      true -> :ok
      false -> {:error, :approval_allowance_mismatch}
      reason -> {:error, reason}
    end
  end

  defp raw(nil, _key), do: nil

  # Balances are configured per wallet, so a proof can tell one wallet's
  # position from another's.
  defp raw(wallet, key),
    do:
      :ash_platform
      |> Application.get_env(:test_staking_balances, %{})
      |> Map.get(wallet, %{})
      |> Map.get(key, Map.fetch!(@balances, key))

  defp setting(key, default), do: Application.get_env(:ash_platform, key, default)

  defp regent(wallet, key), do: scaled(raw(wallet, key), 18)
  defp usdc(wallet, key), do: scaled(raw(wallet, key), 6)

  defp scaled(nil, _decimals), do: nil

  defp scaled(raw, decimals) do
    raw
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
