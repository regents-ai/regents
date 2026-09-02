defmodule AshPlatform.Staking.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Staking.ChainClient

  alias AshPlatform.WalletActions.{Abi, Rpc}

  @read_timeout 12_000
  @chain_id 8453
  @rpc_opts [client_key: :staking_http_client, log_scope: "staking"]

  @impl true
  def protocol_snapshot, do: bounded(fn -> read_protocol() end)

  @impl true
  def wallet_snapshot(wallet_address),
    do: bounded(fn -> read_wallet(Abi.normalize_address!(wallet_address)) end)

  @impl true
  def allowance(signer, amount) do
    with {:ok, block} <- Rpc.latest_block(@rpc_opts),
         {:ok, allowance} <-
           Rpc.call_uint(
             Abi.stake_token_address(),
             Abi.encode_erc20("allowance", [signer, Abi.staking_address()]),
             block,
             @rpc_opts
           ) do
      {:ok, if(allowance >= amount, do: :sufficient, else: :insufficient)}
    end
  end

  # One `latest` block owns every figure below it, and one call returns them
  # all: a partial reading is unavailable, so nothing on the page can pair one
  # block's balance with another's total.
  defp read_protocol do
    with {:ok, block} <- Rpc.latest_block(@rpc_opts),
         :ok <- identified_aggregator(block),
         {:ok,
          [
            paused,
            total_staked,
            denominator,
            available_regent,
            reserved_usdc,
            emission_apr_bps,
            stake_token,
            usdc
          ]} <- Rpc.aggregate3(aggregator(), protocol_calls(), block, @rpc_opts),
         true <- stake_token == Abi.normalize_address!(Abi.stake_token_address()),
         true <- usdc == Abi.normalize_address!(Abi.usdc_address()) do
      capacity = max(denominator - total_staked, 0)

      {:ok,
       %{
         chain_id: @chain_id,
         chain_label: "Base",
         block_number: block.number,
         block_hash: block.hash,
         read_at: DateTime.utc_now(),
         contract_address: Abi.normalize_address!(Abi.staking_address()),
         stake_token_address: stake_token,
         usdc_address: usdc,
         paused: paused,
         total_staked_raw: Integer.to_string(total_staked),
         total_staked: Rpc.format_units(total_staked, 18),
         supply_denominator_raw: Integer.to_string(denominator),
         remaining_capacity_raw: Integer.to_string(capacity),
         remaining_capacity: Rpc.format_units(capacity, 18),
         available_regent_reward_inventory_raw: Integer.to_string(available_regent),
         available_regent_reward_inventory: Rpc.format_units(available_regent, 18),
         reserved_usdc_raw: Integer.to_string(reserved_usdc),
         reserved_usdc: Rpc.format_units(reserved_usdc, 6),
         emission_apr_bps: emission_apr_bps,
         emission_apr_percent: format_bps(emission_apr_bps)
       }}
    else
      false -> {:error, :contract_constants_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  # A wallet reading always takes its own fresh block. A person watching their
  # own transaction confirm needs the block their receipt was mined into or a
  # later one, which a remembered block cannot promise.
  defp read_wallet(wallet) do
    with {:ok, block} <- Rpc.latest_block(@rpc_opts),
         :ok <- identified_aggregator(block),
         {:ok,
          [
            token_balance,
            usdc_balance,
            stake_allowance,
            staked,
            claimable_usdc,
            claimable_regent,
            funded_regent
          ]} <-
           Rpc.aggregate3(aggregator(), wallet_calls(wallet), block, @rpc_opts) do
      {:ok,
       %{
         wallet_block_number: block.number,
         wallet_block_hash: block.hash,
         wallet_address: wallet,
         wallet_token_balance_raw: Integer.to_string(token_balance),
         wallet_token_balance: Rpc.format_units(token_balance, 18),
         wallet_usdc_balance_raw: Integer.to_string(usdc_balance),
         wallet_usdc_balance: Rpc.format_units(usdc_balance, 6),
         wallet_stake_allowance_raw: Integer.to_string(stake_allowance),
         wallet_stake_balance_raw: Integer.to_string(staked),
         wallet_stake_balance: Rpc.format_units(staked, 18),
         wallet_claimable_usdc_raw: Integer.to_string(claimable_usdc),
         wallet_claimable_usdc: Rpc.format_units(claimable_usdc, 6),
         wallet_claimable_regent_raw: Integer.to_string(claimable_regent),
         wallet_claimable_regent: Rpc.format_units(claimable_regent, 18),
         wallet_funded_claimable_regent_raw: Integer.to_string(funded_regent),
         wallet_funded_claimable_regent: Rpc.format_units(funded_regent, 18)
       }}
    end
  end

  # Under the aggregator every sub-call is made by the aggregator, so a read
  # about an account names that account in its own arguments and never relies on
  # who is calling.
  defp protocol_calls do
    staking = Abi.staking_address()

    [
      {staking, Abi.encode_read("paused"), :bool},
      {staking, Abi.encode_read("total_staked"), :uint},
      {staking, Abi.encode_supply_denominator(), :uint},
      {staking, Abi.encode_available_regent_reward_inventory(), :uint},
      {staking, Abi.encode_reserved_usdc(), :uint},
      {staking, Abi.encode_emission_apr_bps(), :uint},
      {staking, Abi.encode_read("stake_token"), :address},
      {staking, Abi.encode_read("usdc"), :address}
    ]
  end

  defp wallet_calls(wallet) do
    staking = Abi.staking_address()
    stake_token = Abi.stake_token_address()

    [
      {stake_token, Abi.encode_erc20("balance_of", [wallet]), :uint},
      {Abi.usdc_address(), Abi.encode_erc20("balance_of", [wallet]), :uint},
      {stake_token, Abi.encode_erc20("allowance", [wallet, staking]), :uint},
      {staking, Abi.encode_read("staked_balance", [wallet]), :uint},
      {staking, Abi.encode_read("claimable_usdc", [wallet]), :uint},
      {staking, Abi.encode_read("claimable_regent", [wallet]), :uint},
      {staking, Abi.encode_read("funded_claimable_regent", [wallet]), :uint}
    ]
  end

  defp aggregator, do: Abi.multicall3_address()

  defp identified_aggregator(block),
    do:
      Rpc.verified_runtime_code(
        aggregator(),
        Abi.multicall3_runtime_keccak256(),
        Abi.multicall3_runtime_bytes(),
        block,
        @rpc_opts
      )

  defp bounded(read) do
    task = Task.async(read)

    case Task.yield(task, @read_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, :chain_timeout}
    end
  end

  defp format_bps(bps) do
    bps
    |> Decimal.new()
    |> Decimal.div(100)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
