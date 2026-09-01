defmodule AshPlatform.Redemption.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Redemption.RpcClient
  alias AshPlatform.WalletActions.{Abi, RedemptionAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @price 80_000_000
  @token_id 42

  setup do
    Stub.install(:redemption_http_client, &call/2)
    Stub.put(%{owner: @wallet})
    :ok
  end

  test "ONE_SAFE_BLOCK: account and selection facts share one canonical Base block" do
    assert {:ok, snapshot} = overview()
    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.safe_hash()
    assert snapshot.wallet_address == @wallet
    assert snapshot.nft_owner == @wallet
    assert snapshot.usdc_allowance_raw == "80000000"
    assert snapshot.max_source_token_id == 999
    assert snapshot.animata_i_held_by_redeemer == 12
    assert snapshot.animata_ii_held_by_redeemer == 12
    assert snapshot.regents_club_ready == 12
    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    assert Enum.uniq(Stub.call_blocks()) == [
             %{blockHash: Stub.safe_hash(), requireCanonical: true}
           ]
  end

  test "OWNER_UNAVAILABLE: an unreadable owner preserves all other current facts" do
    Stub.put(%{owner_of: :unavailable})
    assert {:ok, snapshot} = overview()
    assert snapshot.nft_owner_unavailable
    assert snapshot.nft_owner == nil
    assert snapshot.usdc_balance_raw == "100000000"
    assert snapshot.usdc_allowance_raw == "80000000"
    assert snapshot.claimable_raw == "1000000000000000000"
  end

  test "OWNER_MISMATCH: a readable different owner remains a known chain fact" do
    Stub.put(%{owner: @other})
    assert {:ok, %{nft_owner: @other, nft_owner_unavailable: false}} = overview()
  end

  test "UNAVAILABLE_CHAIN: malformed or wrong-chain facts fail closed" do
    for state <- [
          %{safe_block: :unavailable},
          %{safe_block: %{"number" => "0x20"}},
          %{safe_block: %{"number" => "0x20", "hash" => "0xnope"}},
          %{chain_id: "0x1"}
        ] do
      Stub.put(state)
      assert {:error, _} = overview()
    end
  end

  test "SERVER_ONLY_TRANSPORT: logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :redemption_http_client, Stub.Timeout)

    log =
      capture_log(fn ->
        assert {:error, :chain_unavailable} = RpcClient.overview(nil, nil, nil)
      end)

    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp overview do
    RpcClient.overview(
      @wallet,
      Abi.normalize_address!(RedemptionAbi.animata_i_address()),
      @token_id
    )
  end

  defp call(data, state) do
    if String.starts_with?(data, "0x70a08231") do
      if String.ends_with?(data, Stub.address_word(RedemptionAbi.redeemer_address())),
        do: Stub.uint(Map.get(state, :collection_balance, 12)),
        else: Stub.uint(Map.get(state, :usdc_balance, 100_000_000))
    else
      selector(String.slice(data, 0, 10), state)
    end
  end

  defp selector("0x5817e9d1", _), do: address(RedemptionAbi.animata_i_address())
  defp selector("0x65d32f1e", _), do: address(RedemptionAbi.animata_ii_address())
  defp selector("0xe54b3581", _), do: address(RedemptionAbi.result_collection_address())
  defp selector("0x89a30271", _), do: address(RedemptionAbi.usdc_address())
  defp selector("0x6d667d87", _), do: address(RedemptionAbi.regent_address())
  defp selector("0xd8525aeb", _), do: Stub.uint(@price)
  defp selector("0xa035b1fe", _), do: Stub.uint(@price)
  defp selector("0xde12a91e", _), do: Stub.uint(5_000_000_000_000_000_000_000_000)
  defp selector("0x6e6941c5", _), do: Stub.uint(604_800)
  defp selector("0x17bac052", _), do: Stub.uint(999)
  defp selector("0xdd62ed3e", state), do: Stub.uint(Map.get(state, :allowance, @price))
  defp selector("0x402914f5", _), do: Stub.uint(1_000_000_000_000_000_000)
  defp selector("0x474fc417", _), do: "0x" <> String.duplicate(Stub.hex_word(1), 4)

  defp selector("0xe985e9c5", state),
    do: Stub.uint(if(Map.get(state, :approved, true), do: 1, else: 0))

  defp selector("0x6352211e", state), do: Map.get(state, :owner_of, address(state[:owner]))
  defp address(value), do: "0x" <> Stub.address_word(value)
end
