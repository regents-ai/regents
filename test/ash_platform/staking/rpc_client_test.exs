defmodule AshPlatform.Staking.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Staking.RpcClient
  alias AshPlatform.WalletActions.Abi

  @wallet "0x1111111111111111111111111111111111111111"
  @amount 1_500_000_000_000_000_000

  setup do
    Stub.install(:staking_http_client, &call/2)
    :ok
  end

  test "ONE_LATEST_BLOCK: every overview read is pinned to one canonical Base block" do
    assert {:ok, snapshot} = RpcClient.overview(@wallet)
    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.latest_hash()
    assert snapshot.wallet_address == @wallet
    assert snapshot.wallet_stake_allowance_raw == "0"
    assert snapshot.available_regent_reward_inventory == "250000"
    assert snapshot.reserved_usdc == "125000"
    assert snapshot.emission_apr_percent == "12"
    assert_received {:rpc, "eth_getBlockByNumber", ["latest", false]}

    blocks = Stub.call_blocks()
    assert length(blocks) == 15
    assert Enum.uniq(blocks) == [%{blockHash: Stub.latest_hash(), requireCanonical: true}]
  end

  test "CURRENT_CAPACITY: remaining capacity is floored at zero" do
    Stub.put(%{denominator: 1_000, total_staked: 100})
    assert {:ok, %{remaining_capacity_raw: "900"}} = RpcClient.overview(@wallet)

    Stub.put(%{denominator: 100, total_staked: 250})
    assert {:ok, %{remaining_capacity_raw: "0"}} = RpcClient.overview(@wallet)
  end

  test "CURRENT_ALLOWANCE: a fresh latest-block read reports sufficient or insufficient" do
    Stub.put(%{allowance: @amount})
    assert {:ok, :sufficient} = RpcClient.allowance(@wallet, @amount)
    assert_received {:rpc, "eth_getBlockByNumber", ["latest", false]}

    Stub.put(%{allowance: @amount - 1})
    assert {:ok, :insufficient} = RpcClient.allowance(@wallet, @amount)
  end

  test "UNAVAILABLE_CHAIN: malformed or wrong-chain facts never become zero balances" do
    for state <- [
          %{latest_block: :unavailable},
          %{latest_block: %{"number" => "0x20"}},
          %{latest_block: %{"number" => "later", "hash" => Stub.latest_hash()}},
          %{chain_id: "0x1"}
        ] do
      Stub.put(state)
      assert {:error, _} = RpcClient.overview(@wallet)
    end
  end

  test "SERVER_ONLY_TRANSPORT: logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :staking_http_client, Stub.Timeout)
    log = capture_log(fn -> assert {:error, :chain_unavailable} = RpcClient.overview(nil) end)
    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp call(data, state) do
    values = %{
      Abi.encode_read("stake_token") => word(Abi.stake_token_address()),
      Abi.encode_read("usdc") => word(Abi.usdc_address()),
      Abi.encode_read("paused") => 0,
      Abi.encode_read("total_staked") => Map.get(state, :total_staked, 100),
      Abi.encode_supply_denominator() => Map.get(state, :denominator, 1_000),
      Abi.encode_available_regent_reward_inventory() =>
        Map.get(state, :available_regent, 250_000_000_000_000_000_000_000),
      Abi.encode_reserved_usdc() => Map.get(state, :reserved_usdc, 125_000_000_000),
      Abi.encode_emission_apr_bps() => Map.get(state, :emission_apr_bps, 1_200)
    }

    case Map.fetch(values, data) do
      {:ok, value} -> Stub.uint(value)
      :error -> fallback_call(data, state)
    end
  end

  defp fallback_call("0xdd62ed3e" <> _data, state),
    do: Stub.uint(Map.get(state, :allowance, 0))

  defp fallback_call(_data, state), do: Stub.uint(Map.get(state, :uint, 5))

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)
end
