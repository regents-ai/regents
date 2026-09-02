defmodule AshPlatform.Staking.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Staking.{Facts, RpcClient}
  alias AshPlatform.WalletActions.Abi

  @wallet "0x1111111111111111111111111111111111111111"
  @amount 1_500_000_000_000_000_000

  setup do
    Stub.install(:staking_http_client, &call/2)
    Stub.install_multicall3_identity()
    :ok
  end

  test "ONE_PROTOCOL_CALL: eight contract reads arrive as one aggregate on one block" do
    assert {:ok, snapshot} = RpcClient.protocol_snapshot()

    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.latest_hash()
    assert %DateTime{} = snapshot.read_at
    assert snapshot.paused == false
    assert snapshot.total_staked_raw == "100"
    assert snapshot.supply_denominator_raw == "1000"
    assert snapshot.remaining_capacity_raw == "900"
    assert snapshot.available_regent_reward_inventory == "250000"
    assert snapshot.reserved_usdc == "125000"
    assert snapshot.emission_apr_percent == "12"
    assert snapshot.stake_token_address == Abi.normalize_address!(Abi.stake_token_address())
    assert snapshot.usdc_address == Abi.normalize_address!(Abi.usdc_address())
    assert Enum.sort(Map.keys(snapshot)) == Enum.sort(Facts.protocol_keys())

    one_aggregate(Abi.encode_aggregate3(expected_protocol_calls()))
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

    one_aggregate(Abi.encode_aggregate3(expected_wallet_calls()))
  end

  # Under the aggregator every sub-call is made by Multicall3, so a read about
  # an account that leaned on `msg.sender` would answer about the aggregator.
  test "EXPLICIT_ARGUMENTS: every wallet sub-call names the wallet in its own calldata" do
    assert {:ok, _wallet} = RpcClient.wallet_snapshot(@wallet)
    wallet_word = String.trim_leading(@wallet, "0x")

    for {_target, data} <- expected_wallet_calls() do
      assert String.contains?(data, wallet_word)
    end

    assert one_aggregate(Abi.encode_aggregate3(expected_wallet_calls())) =~ wallet_word
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
      {staking, Abi.encode_available_regent_reward_inventory()},
      {staking, Abi.encode_reserved_usdc()},
      {staking, Abi.encode_emission_apr_bps()},
      {staking, Abi.encode_read("stake_token")},
      {staking, Abi.encode_read("usdc")}
    ]
  end

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

  # Exactly one block-pinned `eth_call` was made, pinned to the head this read
  # took: a second one would fail here rather than pass unnoticed.
  defp one_aggregate(expected) do
    assert [{data, block}] = aggregate_calls()
    assert block == %{blockHash: Stub.latest_hash(), requireCanonical: true}
    assert data == expected
    data
  end

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
      if data == Abi.encode_aggregate3(expected_protocol_calls()),
        do: protocol_words(state),
        else: wallet_words(state)
    )
  end

  defp call("0xdd62ed3e" <> _data, state), do: Stub.uint(Map.get(state, :allowance, 0))

  defp protocol_words(state) do
    [
      Stub.uint(0),
      Stub.uint(Map.get(state, :total_staked, 100)),
      Stub.uint(Map.get(state, :denominator, 1_000)),
      Stub.uint(250_000_000_000_000_000_000_000),
      Stub.uint(125_000_000_000),
      Stub.uint(1_200),
      Stub.uint(Map.get(state, :stake_token) || word(Abi.stake_token_address())),
      Stub.uint(Map.get(state, :usdc) || word(Abi.usdc_address()))
    ]
  end

  defp wallet_words(_state), do: Enum.map(11..17, &Stub.uint/1)

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)
end
