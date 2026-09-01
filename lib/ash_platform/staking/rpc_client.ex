defmodule AshPlatform.Staking.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Staking.ChainClient

  alias AshPlatform.WalletActions.{Abi, Rpc}

  @overview_timeout 12_000
  @chain_id 8453
  @rpc_opts [client_key: :staking_http_client, log_scope: "staking"]

  @impl true
  def overview(wallet_address) do
    task = Task.async(fn -> do_overview(wallet_address) end)

    case Task.yield(task, @overview_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, :chain_timeout}
    end
  end

  # One `safe` block owns every read below it. A partial read is unavailable, so
  # nothing on the page can pair one block's balance with another's total.
  defp do_overview(wallet_address) do
    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, paused} <- read_bool("paused", block),
         {:ok, total_staked} <- read_uint("total_staked", block),
         {:ok, denominator} <-
           Rpc.call_uint(
             Abi.staking_address(),
             Abi.encode_supply_denominator(),
             block,
             @rpc_opts
           ),
         {:ok, [available_regent, reserved_usdc, emission_apr_bps]} <-
           parallel_reads([
             fn ->
               Rpc.call_uint(
                 Abi.staking_address(),
                 Abi.encode_available_regent_reward_inventory(),
                 block,
                 @rpc_opts
               )
             end,
             fn ->
               Rpc.call_uint(
                 Abi.staking_address(),
                 Abi.encode_reserved_usdc(),
                 block,
                 @rpc_opts
               )
             end,
             fn ->
               Rpc.call_uint(
                 Abi.staking_address(),
                 Abi.encode_emission_apr_bps(),
                 block,
                 @rpc_opts
               )
             end
           ]),
         {:ok, stake_token} <- read_address("stake_token", block),
         {:ok, usdc} <- read_address("usdc", block),
         true <- stake_token == Abi.normalize_address!(Abi.stake_token_address()),
         true <- usdc == Abi.normalize_address!(Abi.usdc_address()),
         {:ok, account} <- account_reads(wallet_address, stake_token, usdc, block) do
      capacity = max(denominator - total_staked, 0)

      {:ok,
       Map.merge(account, %{
         chain_id: @chain_id,
         chain_label: "Base",
         block_number: block.number,
         block_hash: block.hash,
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
       })}
    else
      false -> {:error, :contract_constants_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def allowance(signer, amount) do
    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
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

  defp account_reads(nil, _stake_token, _usdc, _block) do
    {:ok,
     %{
       wallet_address: nil,
       wallet_token_balance_raw: nil,
       wallet_token_balance: nil,
       wallet_usdc_balance_raw: nil,
       wallet_usdc_balance: nil,
       wallet_stake_allowance_raw: nil,
       wallet_stake_balance_raw: nil,
       wallet_stake_balance: nil,
       wallet_claimable_usdc_raw: nil,
       wallet_claimable_usdc: nil,
       wallet_claimable_regent_raw: nil,
       wallet_claimable_regent: nil,
       wallet_funded_claimable_regent_raw: nil,
       wallet_funded_claimable_regent: nil
     }}
  end

  defp account_reads(wallet_address, stake_token, usdc, block) do
    wallet = Abi.normalize_address!(wallet_address)

    with {:ok, token_balance} <- balance_of(stake_token, wallet, block),
         {:ok, usdc_balance} <- balance_of(usdc, wallet, block),
         {:ok, stake_allowance} <-
           Rpc.call_uint(
             stake_token,
             Abi.encode_erc20("allowance", [wallet, Abi.staking_address()]),
             block,
             @rpc_opts
           ),
         {:ok, staked} <- read_uint("staked_balance", [wallet], block),
         {:ok, claimable_usdc} <- read_uint("claimable_usdc", [wallet], block),
         {:ok, claimable_regent} <- read_uint("claimable_regent", [wallet], block),
         {:ok, funded_regent} <- read_uint("funded_claimable_regent", [wallet], block) do
      {:ok,
       %{
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

  defp balance_of(token, wallet, block),
    do: Rpc.call_uint(token, Abi.encode_erc20("balance_of", [wallet]), block, @rpc_opts)

  defp read_uint(id, block), do: read_uint(id, [], block)

  defp read_uint(id, arguments, block),
    do: Rpc.call_uint(Abi.staking_address(), Abi.encode_read(id, arguments), block, @rpc_opts)

  defp read_bool(id, block),
    do: Rpc.call_bool(Abi.staking_address(), Abi.encode_read(id), block, @rpc_opts)

  defp read_address(id, block),
    do: Rpc.call_address(Abi.staking_address(), Abi.encode_read(id), block, @rpc_opts)

  defp format_bps(bps) do
    bps
    |> Decimal.new()
    |> Decimal.div(100)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp parallel_reads(reads) do
    reads
    |> Task.async_stream(& &1.(),
      max_concurrency: length(reads),
      ordered: true,
      timeout: @overview_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, value}}, {:ok, values} -> {:cont, {:ok, [value | values]}}
      {:ok, {:error, reason}}, _ -> {:halt, {:error, reason}}
      _, _ -> {:halt, {:error, :chain_timeout}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
