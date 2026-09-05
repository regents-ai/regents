defmodule AshPlatform.Staking.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Staking.{Facts, RpcClient, Supply}
  alias AshPlatform.WalletActions.Abi

  @wallet "0x1111111111111111111111111111111111111111"
  @treasury "0x3333333333333333333333333333333333333333"
  @amount 1_500_000_000_000_000_000

  # One REGENT, and the four holdings this stubbed chain keeps out of
  # circulation: twenty billion in the treasury, two billion in the Animata
  # redeemer, five billion of reward inventory, and the forty billion of vault
  # the reader carries itself. A hundred billion less those leaves thirty-three.
  @regent 1_000_000_000_000_000_000
  @treasury_held 20_000_000_000 * @regent
  @redeemer_held 2_000_000_000 * @regent
  @reward_inventory 5_000_000_000 * @regent

  # Seven days of Base blocks, and the largest range a public endpoint answers
  # `eth_getLogs` over. Both are stated here rather than read from the reader, so
  # a change to either has to be made twice on purpose.
  @window_blocks 302_400
  @chunk_blocks 10_000

  # High enough that a whole seven-day window sits below it, so the window
  # arithmetic is proved against a block a real reading could have.
  @head 40_000_000

  # The window ends at @head and both ends of it are counted, so it holds
  # @window_blocks blocks only if it begins one block after @head - @window_blocks.
  @window_start @head - @window_blocks + 1

  setup do
    Stub.install(:staking_http_client, &call/2)
    Stub.install_multicall3_identity()
    :ok
  end

  test "ONE_PROTOCOL_CALL: the contract reads arrive on one block, the treasury's balance too" do
    assert {:ok, snapshot} = RpcClient.protocol_snapshot()

    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.latest_hash()
    assert %DateTime{} = snapshot.read_at
    assert snapshot.paused == false
    assert snapshot.total_staked_raw == "100"
    assert snapshot.remaining_capacity_raw == "900"
    assert snapshot.usdc_received_lifetime_raw == "125000000000"
    assert snapshot.usdc_received_lifetime == "125000"
    assert snapshot.regent_total_supply_raw == "100000000000000000000000000000"
    assert snapshot.regent_total_supply == "100000000000"
    assert snapshot.regent_circulating_supply_raw == "33000000000000000000000000000"
    assert snapshot.regent_circulating_supply == "33000000000"
    assert snapshot.emission_apr_percent == "12"
    assert snapshot.stake_token_address == Abi.normalize_address!(Abi.stake_token_address())
    assert snapshot.usdc_address == Abi.normalize_address!(Abi.usdc_address())

    assert Enum.sort(Map.keys(snapshot)) ==
             Enum.sort(Facts.protocol_keys() -- [:regent_price_usd])

    aggregates([
      Abi.encode_aggregate3(expected_protocol_calls()),
      Abi.encode_aggregate3(expected_treasury_calls())
    ])
  end

  # Every holding is subtracted, so a reading that quietly dropped one would
  # leave more REGENT circulating than there is.
  test "CIRCULATING_SUPPLY: what circulates is the supply less all four holdings" do
    Stub.put(%{treasury_held: 0, redeemer_held: 0, reward_inventory: 0})
    assert {:ok, %{regent_circulating_supply: "60000000000"}} = RpcClient.protocol_snapshot()

    # More held than there is supply is no supply at all, never a negative one.
    Stub.put(%{treasury_held: 100_000_000_000 * @regent})
    assert {:ok, %{regent_circulating_supply_raw: "0"}} = RpcClient.protocol_snapshot()
  end

  # A selector that named some other function would return some other number
  # while every other proof here still passed, so the two reads this page adds
  # are derived from the signatures the pinned ABI declares.
  test "PINNED_SELECTORS: each locally encoded read is the Keccak-256 of its own signature" do
    assert Abi.total_usdc_received_signature() == "totalUsdcReceived()"
    assert Abi.erc20_total_supply_signature() == "totalSupply()"

    assert Abi.treasury_recipient_signature() == "treasuryRecipient()"
    assert Abi.reward_inventory_signature() == "availableRegentRewardInventory()"

    assert selector(Abi.total_usdc_received_signature()) == Abi.encode_total_usdc_received()
    assert selector(Abi.erc20_total_supply_signature()) == Abi.encode_erc20_total_supply()
    assert selector(Abi.treasury_recipient_signature()) == Abi.encode_treasury_recipient()
    assert selector(Abi.reward_inventory_signature()) == Abi.encode_reward_inventory()
  end

  # The window is the chain's own: it ends at the block this reading was taken
  # at and holds exactly seven days of blocks, that last one among them, and the
  # pieces it is asked for in cover that range once each and reach nothing
  # outside it.
  test "SEVEN_DAY_WINDOW: the deposit range is asked for in contiguous endpoint-sized pieces" do
    head(@head)

    assert {:ok, snapshot} = RpcClient.protocol_snapshot()
    assert snapshot.usdc_received_from_block == @window_start

    ranges = log_ranges()
    {first_from, _first_to} = List.first(ranges)
    {_last_from, last_to} = List.last(ranges)

    assert length(ranges) == 31
    assert first_from == @window_start
    assert last_to == @head
    assert last_to - first_from + 1 == @window_blocks

    for {from, to} <- ranges do
      assert to >= from
      assert to - from + 1 <= @chunk_blocks
    end

    # Each piece begins exactly where the one before it ended, so nothing in the
    # window is asked for twice and nothing is skipped.
    for [{_from, to}, {next_from, _next_to}] <- Enum.chunk_every(ranges, 2, 1, :discard) do
      assert next_from == to + 1
    end
  end

  test "SEVEN_DAY_SUM: every recorded deposit in the window is added up across the pieces" do
    head(@head)

    Stub.put(%{
      logs: [
        revenue_log(@window_start, 1_500_000),
        revenue_log(@head - 12_345, 2_250_000),
        revenue_log(@head, 400_000),
        # The block before the window opens, and a deposit some other contract
        # recorded: both are somebody else's history and neither belongs in
        # this figure.
        revenue_log(@window_start - 1, 9_000_000),
        %{revenue_log(@head, 7_000_000) | "address" => Abi.usdc_address()}
      ]
    })

    assert {:ok, snapshot} = RpcClient.protocol_snapshot()
    assert snapshot.usdc_received_7d_raw == "4150000"
    assert snapshot.usdc_received_7d == "4.15"
  end

  test "SEVEN_DAY_SUM_IS_ZERO: a window with no deposits is zero rather than unavailable" do
    assert {:ok, %{usdc_received_7d_raw: "0", usdc_received_7d: "0"}} =
             RpcClient.protocol_snapshot()
  end

  # A total assembled from the pieces that happened to answer would understate
  # what the contract registered, so a refused piece takes the seven-day figure
  # with it. It takes nothing else: the contract already answered for every
  # other figure, and that answer stands.
  test "FAILING_PIECE: a refused piece of the window costs that figure and nothing else" do
    head(@head)
    Stub.put(%{refused_log_range: @window_start + 3 * @chunk_blocks})

    log =
      capture_log(fn ->
        assert {:ok, snapshot} = RpcClient.protocol_snapshot()

        assert snapshot.usdc_received_7d == :unavailable
        assert snapshot.usdc_received_7d_raw == :unavailable
        assert snapshot.usdc_received_from_block == :unavailable

        # Every figure the contract itself answered for is there and exact.
        assert snapshot.block_number == @head
        assert snapshot.total_staked_raw == "100"
        assert snapshot.remaining_capacity_raw == "900"
        assert snapshot.usdc_received_lifetime_raw == "125000000000"
        assert snapshot.regent_total_supply == "100000000000"

        assert Enum.sort(Map.keys(snapshot)) ==
                 Enum.sort(Facts.protocol_keys() -- [:regent_price_usd])
      end)

    # The log names the stretch of blocks that failed and why, and never the
    # endpoint it asked.
    failed_from = @window_start + 3 * @chunk_blocks
    assert log =~ "seven-day USDC window unavailable"
    assert log =~ "blocks #{failed_from}..#{failed_from + @chunk_blocks - 1}"
    refute log =~ "http"
  end

  # A log this contract did not emit, or one carrying another event's shape,
  # fails the sum rather than being skipped past. The sum is the seven-day
  # figure alone, so nothing else in the reading answers for it.
  test "MALFORMED_LOG: a log that does not decode fails the seven-day figure" do
    Stub.put(%{logs: [%{revenue_log(0x20, 1_000_000) | "data" => "0x"}]})

    capture_log(fn ->
      assert {:ok, %{usdc_received_7d: :unavailable, usdc_received_lifetime: "125000"}} =
               RpcClient.protocol_snapshot()
    end)
  end

  test "ONE_WALLET_CALL: seven wallet reads arrive as one aggregate on a fresh block" do
    assert {:ok, wallet} = RpcClient.wallet_snapshot(@wallet)

    assert wallet.wallet_block_number == 0x20
    assert wallet.wallet_block_hash == Stub.latest_hash()
    assert wallet.wallet_address == @wallet
    assert wallet.wallet_token_balance_raw == "11"
    assert wallet.wallet_usdc_balance_raw == "12"
    assert wallet.wallet_stake_allowance_raw == "13"
    assert wallet.wallet_stake_balance_raw == "14"
    assert wallet.wallet_claimable_usdc_raw == "15"
    assert wallet.wallet_claimable_regent_raw == "16"
    assert wallet.wallet_funded_claimable_regent_raw == "17"
    assert wallet.wallet_token_balance == "0.000000000000000011"
    assert wallet.wallet_usdc_balance == "0.000012"
    assert Enum.sort(Map.keys(wallet)) == Enum.sort(Facts.wallet_keys())

    aggregates([Abi.encode_aggregate3(expected_wallet_calls())])
  end

  # Under the aggregator every sub-call is made by Multicall3, so a read about
  # an account that leaned on `msg.sender` would answer about the aggregator.
  test "EXPLICIT_ARGUMENTS: every wallet sub-call names the wallet in its own calldata" do
    assert {:ok, _wallet} = RpcClient.wallet_snapshot(@wallet)
    wallet_word = String.trim_leading(@wallet, "0x")

    for {_target, data} <- expected_wallet_calls() do
      assert String.contains?(data, wallet_word)
    end

    assert [data] = aggregates([Abi.encode_aggregate3(expected_wallet_calls())])
    assert data =~ wallet_word
  end

  test "NON_CANONICAL_BLOCK: a block that moved fails the read instead of answering it" do
    Stub.put(%{canonical_block_hash: "0x" <> String.duplicate("9d", 32)})

    assert {:error, :chain_unavailable} = RpcClient.protocol_snapshot()
    assert {:error, :chain_unavailable} = RpcClient.wallet_snapshot(@wallet)
  end

  test "REVERTING_SUB_CALL: one refused sub-call makes the whole reading unavailable" do
    Application.put_env(:ash_platform, :staking_http_client, Stub.UnsupportedCall)

    assert {:error, :chain_unavailable} = RpcClient.protocol_snapshot()
    assert {:error, :chain_unavailable} = RpcClient.wallet_snapshot(@wallet)
  end

  test "CONSTANTS_MISMATCH: a contract naming other tokens refuses the whole snapshot" do
    Stub.put(%{stake_token: 1})
    assert {:error, :contract_constants_mismatch} = RpcClient.protocol_snapshot()

    Stub.put(%{stake_token: nil, usdc: 2})
    assert {:error, :contract_constants_mismatch} = RpcClient.protocol_snapshot()
  end

  test "AGGREGATOR_IDENTITY: an unrecognised aggregator refuses the reading before it is made" do
    Stub.put(%{code: Stub.runtime_code(Abi.multicall3_runtime_bytes() - 1)})
    assert {:error, :runtime_mismatch} = RpcClient.protocol_snapshot()

    Stub.put(%{code: "0x"})
    assert {:error, :runtime_mismatch} = RpcClient.wallet_snapshot(@wallet)
  end

  test "IDENTITY_IS_PINNED: the aggregator is identified at the same block the reads use" do
    assert {:ok, _snapshot} = RpcClient.protocol_snapshot()

    assert_received {:rpc, "eth_getCode", [address, %{blockHash: hash, requireCanonical: true}]}

    assert String.downcase(address) == String.downcase(Abi.multicall3_address())
    assert hash == Stub.latest_hash()
  end

  test "CURRENT_ALLOWANCE: a fresh latest-block read reports sufficient or insufficient" do
    Stub.put(%{allowance: @amount})
    assert {:ok, :sufficient} = RpcClient.allowance(@wallet, @amount)
    assert_received {:rpc, "eth_getBlockByNumber", ["latest", false]}

    Stub.put(%{allowance: @amount - 1})
    assert {:ok, :insufficient} = RpcClient.allowance(@wallet, @amount)
  end

  test "CURRENT_CAPACITY: remaining capacity is floored at zero" do
    Stub.put(%{denominator: 100, total_staked: 250})
    assert {:ok, %{remaining_capacity_raw: "0"}} = RpcClient.protocol_snapshot()
  end

  test "UNAVAILABLE_CHAIN: malformed or wrong-chain facts never become zero balances" do
    for state <- [
          %{latest_block: :unavailable},
          %{latest_block: %{"number" => "0x20"}},
          %{latest_block: %{"number" => "later", "hash" => Stub.latest_hash()}},
          %{chain_id: "0x1"}
        ] do
      Stub.put(state)
      assert {:error, _} = RpcClient.protocol_snapshot()
      assert {:error, _} = RpcClient.wallet_snapshot(@wallet)
    end
  end

  test "SERVER_ONLY_TRANSPORT: logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :staking_http_client, Stub.Timeout)

    log =
      capture_log(fn -> assert {:error, :chain_unavailable} = RpcClient.protocol_snapshot() end)

    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp expected_protocol_calls do
    staking = Abi.staking_address()

    [
      {staking, Abi.encode_read("paused")},
      {staking, Abi.encode_read("total_staked")},
      {staking, Abi.encode_supply_denominator()},
      {staking, Abi.encode_total_usdc_received()},
      {staking, Abi.encode_emission_apr_bps()},
      {staking, Abi.encode_read("stake_token")},
      {staking, Abi.encode_read("usdc")},
      {Abi.stake_token_address(), Abi.encode_erc20_total_supply()},
      {staking, Abi.encode_treasury_recipient()},
      {staking, Abi.encode_reward_inventory()},
      {Abi.stake_token_address(), Abi.encode_erc20("balance_of", [Supply.animata_redeemer()])}
    ]
  end

  defp expected_treasury_calls,
    do: [{Abi.stake_token_address(), Abi.encode_erc20("balance_of", [@treasury])}]

  defp head(number),
    do:
      Stub.put(%{latest_block: %{"number" => hex_quantity(number), "hash" => Stub.latest_hash()}})

  defp selector(signature), do: signature |> Abi.topic0() |> String.slice(0, 10)

  # One `USDCRevenueDeposited` exactly as the contract writes it: three indexed
  # topics beside the event's own, and four data words whose first is the
  # `amountReceived` this sum is made of.
  defp revenue_log(block_number, amount) do
    %{
      "address" => Abi.staking_address(),
      "topics" => [
        Abi.event_topic(:usdc_revenue_deposited)
        | List.duplicate("0x" <> Stub.hex_word(0), 3)
      ],
      "data" => "0x" <> Stub.hex_word(amount) <> String.duplicate(Stub.hex_word(0), 3),
      "blockNumber" => hex_quantity(block_number)
    }
  end

  # Every block range this reading asked the endpoint for, in order.
  defp log_ranges(ranges \\ []) do
    receive do
      {:rpc, "eth_getLogs", [filter]} ->
        log_ranges([{quantity(filter.fromBlock), quantity(filter.toBlock)} | ranges])

      {:rpc, _method, _params} ->
        log_ranges(ranges)
    after
      0 -> Enum.sort(ranges)
    end
  end

  defp hex_quantity(value), do: "0x" <> (value |> Integer.to_string(16) |> String.downcase())

  defp quantity("0x" <> hex), do: String.to_integer(hex, 16)

  defp expected_wallet_calls do
    staking = Abi.staking_address()
    stake_token = Abi.stake_token_address()

    [
      {stake_token, Abi.encode_erc20("balance_of", [@wallet])},
      {Abi.usdc_address(), Abi.encode_erc20("balance_of", [@wallet])},
      {stake_token, Abi.encode_erc20("allowance", [@wallet, staking])},
      {staking, Abi.encode_read("staked_balance", [@wallet])},
      {staking, Abi.encode_read("claimable_usdc", [@wallet])},
      {staking, Abi.encode_read("claimable_regent", [@wallet])},
      {staking, Abi.encode_read("funded_claimable_regent", [@wallet])}
    ]
  end

  # Exactly these block-pinned `eth_call`s were made, in this order and every
  # one of them pinned to the head this read took: another would fail here
  # rather than pass unnoticed, and one taken at a second block likewise.
  defp aggregates(expected) do
    calls = Enum.reverse(aggregate_calls())
    assert Enum.map(calls, &elem(&1, 1)) == List.duplicate(block_pin(), length(expected))
    assert Enum.map(calls, &elem(&1, 0)) == expected
    Enum.map(calls, &elem(&1, 0))
  end

  defp block_pin, do: %{blockHash: Stub.latest_hash(), requireCanonical: true}

  defp aggregate_calls(calls \\ []) do
    receive do
      {:rpc, "eth_call", [%{data: data}, block]} -> aggregate_calls([{data, block} | calls])
      {:rpc, _method, _params} -> aggregate_calls(calls)
    after
      0 -> calls
    end
  end

  # One aggregate is one `eth_call`, so the stub answers it by decoding the sub
  # calls the reader asked for and returning one word for each in order.
  defp call("0x82ad56cb" <> _rest = data, state) do
    Stub.aggregate3_result(
      cond do
        data == Abi.encode_aggregate3(expected_protocol_calls()) -> protocol_words(state)
        data == Abi.encode_aggregate3(expected_treasury_calls()) -> treasury_words(state)
        true -> wallet_words(state)
      end
    )
  end

  defp call("0xdd62ed3e" <> _data, state), do: Stub.uint(Map.get(state, :allowance, 0))

  defp protocol_words(state) do
    [
      Stub.uint(0),
      Stub.uint(Map.get(state, :total_staked, 100)),
      Stub.uint(Map.get(state, :denominator, 1_000)),
      Stub.uint(125_000_000_000),
      Stub.uint(1_200),
      Stub.uint(Map.get(state, :stake_token) || word(Abi.stake_token_address())),
      Stub.uint(Map.get(state, :usdc) || word(Abi.usdc_address())),
      Stub.uint(100_000_000_000_000_000_000_000_000_000),
      Stub.uint(word(@treasury)),
      Stub.uint(Map.get(state, :reward_inventory, @reward_inventory)),
      Stub.uint(Map.get(state, :redeemer_held, @redeemer_held))
    ]
  end

  defp treasury_words(state), do: [Stub.uint(Map.get(state, :treasury_held, @treasury_held))]

  defp wallet_words(_state), do: Enum.map(11..17, &Stub.uint/1)

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)
end
