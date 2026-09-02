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

  # The two readings are taken at different blocks on purpose: a proof that
  # pairs one map's figure with the other's block fails here rather than in
  # production.
  @protocol_block 1_234
  @wallet_block 1_240

  def protocol_block, do: @protocol_block
  def wallet_block, do: @wallet_block

  # An unavailable Base read is its own outcome: it is never a zero balance and
  # never evidence about which wallet is asking.
  @impl true
  def protocol_snapshot do
    report_read(:protocol)

    case Application.get_env(:ash_platform, :test_staking_protocol_error) do
      nil -> {:ok, protocol()}
      reason -> {:error, reason}
    end
  end

  @impl true
  def wallet_snapshot(wallet) do
    report_read(:wallet)

    case Application.get_env(:ash_platform, :test_staking_wallet_error) do
      nil -> {:ok, wallet_facts(wallet)}
      reason -> {:error, reason}
    end
  end

  @impl true
  def allowance(_wallet, amount) do
    current = Application.get_env(:ash_platform, :test_staking_allowance, 0)
    {:ok, if(current >= amount, do: :sufficient, else: :insufficient)}
  end

  # A test may watch the process doing a read, so an ordering proof can wait for
  # that read to finish rather than for a duration.
  defp report_read(scope) do
    case Application.get_env(:ash_platform, :test_staking_read_watcher) do
      nil -> :ok
      test -> send(test, {:staking_read, scope, self()})
    end
  end

  defp protocol do
    total = String.to_integer(@total_staked)
    denominator = String.to_integer(setting(:test_staking_denominator, @denominator))
    capacity = max(denominator - total, 0)

    %{
      chain_id: 8453,
      chain_label: "Base",
      block_number: setting(:test_staking_protocol_block, @protocol_block),
      block_hash: "0x" <> String.duplicate("1b", 32),
      read_at: setting(:test_staking_read_at, DateTime.utc_now()),
      contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
      stake_token_address: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
      usdc_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      paused: Application.get_env(:ash_platform, :test_staking_paused, false),
      total_staked_raw: @total_staked,
      total_staked: scaled(@total_staked, 18),
      supply_denominator_raw: Integer.to_string(denominator),
      remaining_capacity_raw: Integer.to_string(capacity),
      remaining_capacity: scaled(Integer.to_string(capacity), 18),
      available_regent_reward_inventory_raw: "250000000000000000000000",
      available_regent_reward_inventory: "250000",
      reserved_usdc_raw: "125000000000",
      reserved_usdc: "125000",
      emission_apr_bps: 1_200,
      emission_apr_percent: "12"
    }
  end

  defp wallet_facts(wallet) do
    %{
      wallet_block_number: setting(:test_staking_wallet_block, @wallet_block),
      wallet_block_hash: "0x" <> String.duplicate("2c", 32),
      wallet_address: wallet,
      wallet_token_balance_raw: raw(wallet, :token),
      wallet_token_balance: regent(wallet, :token),
      wallet_usdc_balance_raw: raw(wallet, :usdc_wallet),
      wallet_usdc_balance: usdc(wallet, :usdc_wallet),
      wallet_stake_allowance_raw: "0",
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

  defp scaled(raw, decimals) do
    raw
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
