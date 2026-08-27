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

  test "ONE_SAFE_BLOCK: every overview read is pinned to one canonical Base block" do
    assert {:ok, snapshot} = RpcClient.overview(@wallet)
    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.safe_hash()
    assert snapshot.wallet_address == @wallet
    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    blocks = Stub.call_blocks()
    assert Enum.count_until(blocks, 8) == 8
    assert Enum.uniq(blocks) == [%{blockHash: Stub.safe_hash(), requireCanonical: true}]
  end

  test "CURRENT_CAPACITY: remaining capacity is floored at zero" do
    Stub.put(%{denominator: 1_000, total_staked: 100})
    assert {:ok, %{remaining_capacity_raw: "900"}} = RpcClient.overview(@wallet)

    Stub.put(%{denominator: 100, total_staked: 250})
    assert {:ok, %{remaining_capacity_raw: "0"}} = RpcClient.overview(@wallet)
  end

  test "CURRENT_ALLOWANCE: a fresh safe-block read reports sufficient or insufficient" do
    Stub.put(%{allowance: @amount})
    assert {:ok, :sufficient} = RpcClient.allowance(@wallet, @amount)
    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    Stub.put(%{allowance: @amount - 1})
    assert {:ok, :insufficient} = RpcClient.allowance(@wallet, @amount)
  end

  test "UNAVAILABLE_CHAIN: malformed or wrong-chain facts never become zero balances" do
    for state <- [
          %{safe_block: :unavailable},
          %{safe_block: %{"number" => "0x20"}},
          %{safe_block: %{"number" => "later", "hash" => Stub.safe_hash()}},
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
    cond do
      data == Abi.encode_read("stake_token") -> Stub.uint(word(Abi.stake_token_address()))
      data == Abi.encode_read("usdc") -> Stub.uint(word(Abi.usdc_address()))
      data == Abi.encode_read("paused") -> Stub.uint(0)
      data == Abi.encode_read("total_staked") -> Stub.uint(Map.get(state, :total_staked, 100))
      data == Abi.encode_supply_denominator() -> Stub.uint(Map.get(state, :denominator, 1_000))
      String.starts_with?(data, "0xdd62ed3e") -> Stub.uint(Map.get(state, :allowance, 0))
      true -> Stub.uint(Map.get(state, :uint, 5))
    end
  end

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)
end
