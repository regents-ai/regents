defmodule AshPlatform.Staking.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Staking.ChainClient

  alias AshPlatform.WalletActions.{Abi, Rpc}

  @read_timeout 20_000
  @chain_id 8453
  @rpc_opts [client_key: :staking_http_client, log_scope: "staking"]

  # Base confirms a block about every two seconds, so seven days is 302,400 of
  # them. The window is counted back from the block this reading was taken at
  # and never from the clock, so the figure and the block beside it always
  # describe the same stretch of chain. Both ends of the range are counted, so
  # the window's first block is 302,399 blocks before its last.
  @window_blocks 302_400

  # A public Base endpoint answers `eth_getLogs` over at most ten thousand
  # blocks, so the window is asked for in that many at a time. The requests go
  # out together, a few at a time, and any one of them failing fails the whole
  # reading.
  @chunk_blocks 10_000
  @chunk_concurrency 8

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

  # One `latest` block owns every figure below it: one call returns all the
  # contract's current answers, and the deposit window ends at that same block,
  # so nothing on the page can pair one block's total with another's history. A
  # partial reading is unavailable rather than shown.
  defp read_protocol do
    with {:ok, block} <- Rpc.latest_block(@rpc_opts),
         :ok <- identified_aggregator(block),
         {:ok,
          [
            paused,
            total_staked,
            denominator,
            usdc_received,
            emission_apr_bps,
            stake_token,
            usdc,
            regent_total_supply
          ]} <- Rpc.aggregate3(aggregator(), protocol_calls(), block, @rpc_opts),
         true <- stake_token == Abi.normalize_address!(Abi.stake_token_address()),
         true <- usdc == Abi.normalize_address!(Abi.usdc_address()),
         from_block <- max(block.number - @window_blocks + 1, 0),
         {:ok, usdc_received_window} <- usdc_received_between(from_block, block.number) do
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
         remaining_capacity_raw: Integer.to_string(capacity),
         usdc_received_from_block: from_block,
         usdc_received_7d_raw: Integer.to_string(usdc_received_window),
         usdc_received_7d: Rpc.format_units(usdc_received_window, 6),
         usdc_received_lifetime_raw: Integer.to_string(usdc_received),
         usdc_received_lifetime: Rpc.format_units(usdc_received, 6),
         regent_total_supply_raw: Integer.to_string(regent_total_supply),
         regent_total_supply: Rpc.format_units(regent_total_supply, 18),
         emission_apr_bps: emission_apr_bps,
         emission_apr_percent: format_bps(emission_apr_bps)
       }}
    else
      false -> {:error, :contract_constants_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  # Every deposit the contract recorded over the window, added up from its own
  # logs. The range is asked for in endpoint-sized pieces at once rather than
  # one after another, and a piece that fails takes the whole reading with it:
  # a total missing one piece would understate what the contract registered,
  # and the shared reading treats a failure as "the previous reading stays".
  defp usdc_received_between(from_block, to_block) do
    from_block
    |> chunks(to_block)
    |> Task.async_stream(&chunk_received/1,
      max_concurrency: @chunk_concurrency,
      ordered: false,
      timeout: @read_timeout
    )
    |> Enum.reduce_while({:ok, 0}, fn
      {:ok, {:ok, received}}, {:ok, total} -> {:cont, {:ok, total + received}}
      {:ok, {:error, reason}}, _total -> {:halt, {:error, reason}}
      {:exit, _reason}, _total -> {:halt, {:error, :chain_unavailable}}
    end)
  end

  defp chunks(from_block, to_block) do
    from_block
    |> Stream.iterate(&(&1 + @chunk_blocks))
    |> Stream.take_while(&(&1 <= to_block))
    |> Enum.map(&{&1, min(&1 + @chunk_blocks - 1, to_block)})
  end

  defp chunk_received({from_block, to_block}) do
    with {:ok, logs} <-
           Rpc.request(
             "eth_getLogs",
             [
               %{
                 address: Abi.staking_address(),
                 topics: [Abi.event_topic(:usdc_revenue_deposited)],
                 fromBlock: hex_quantity(from_block),
                 toBlock: hex_quantity(to_block)
               }
             ],
             @rpc_opts
           ),
         {:ok, received} <- Abi.usdc_revenue_received(logs) do
      {:ok, received}
    else
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hex_quantity(value), do: "0x" <> (value |> Integer.to_string(16) |> String.downcase())

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
  #
  # The last sub-call reads the REGENT token rather than the staking contract.
  # It names the pinned token address, and the `stake_token` read beside it
  # proves the staking contract answers with that same address before any of
  # this reading is believed.
  defp protocol_calls do
    staking = Abi.staking_address()

    [
      {staking, Abi.encode_read("paused"), :bool},
      {staking, Abi.encode_read("total_staked"), :uint},
      {staking, Abi.encode_supply_denominator(), :uint},
      {staking, Abi.encode_total_usdc_received(), :uint},
      {staking, Abi.encode_emission_apr_bps(), :uint},
      {staking, Abi.encode_read("stake_token"), :address},
      {staking, Abi.encode_read("usdc"), :address},
      {Abi.stake_token_address(), Abi.encode_erc20_total_supply(), :uint}
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
