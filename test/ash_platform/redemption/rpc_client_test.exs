defmodule AshPlatform.Redemption.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Redemption.RpcClient
  alias AshPlatform.WalletActions.{Abi, RedemptionAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @price 80_000_000
  @payout 5_000_000_000_000_000_000_000_000
  @claimable 1_000_000_000_000_000_000
  @token_id 42

  setup do
    Stub.install(:redemption_http_client, &call/2)
    Stub.install_multicall3_identity()
    Stub.put(%{owner: @wallet})
    :ok
  end

  test "ONE_PUBLIC_CALL: constants and all three collection counts arrive as one aggregate" do
    assert {:ok, snapshot} = RpcClient.overview(nil, nil, nil)

    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.latest_hash()
    assert snapshot.redeemer_address == normalized(RedemptionAbi.redeemer_address())
    assert snapshot.animata_i_address == normalized(RedemptionAbi.animata_i_address())
    assert snapshot.animata_ii_address == normalized(RedemptionAbi.animata_ii_address())

    assert snapshot.result_collection_address ==
             normalized(RedemptionAbi.result_collection_address())

    assert snapshot.usdc_address == normalized(RedemptionAbi.usdc_address())
    assert snapshot.regent_address == normalized(RedemptionAbi.regent_address())
    assert snapshot.price_raw == "80000000"
    assert snapshot.price == "80"
    assert snapshot.payout_raw == Integer.to_string(@payout)
    assert snapshot.payout == "5000000"
    assert snapshot.vest_duration_seconds == 604_800
    assert snapshot.max_source_token_id == 999
    assert snapshot.animata_i_held_by_redeemer == 12
    assert snapshot.animata_ii_held_by_redeemer == 13
    assert snapshot.regents_club_ready == 14
    assert snapshot.wallet_address == nil
    assert snapshot.selected_collection == nil
    assert snapshot.token_id == nil
    assert snapshot.nft_owner == nil
    assert snapshot.nft_owner_unavailable == false
    assert snapshot.nft_approved == nil
    assert snapshot.usdc_balance == nil
    assert snapshot.claimable_raw == nil
    assert snapshot.vest_start == nil

    assert pinned_calls() == [{aggregator(), aggregate(protocol_calls()), latest()}]
  end

  test "ONE_WALLET_CALL: account and approval facts join the aggregate; only the owner is read alone" do
    assert {:ok, snapshot} = overview()

    assert snapshot.wallet_address == @wallet
    assert snapshot.selected_collection == animata_i()
    assert snapshot.token_id == @token_id
    assert snapshot.nft_owner == @wallet
    assert snapshot.nft_owner_unavailable == false
    assert snapshot.nft_approved == true
    assert snapshot.usdc_balance_raw == "100000000"
    assert snapshot.usdc_balance == "100"
    assert snapshot.usdc_allowance_raw == "80000000"
    assert snapshot.usdc_allowance == "80"
    assert snapshot.claimable_raw == Integer.to_string(@claimable)
    assert snapshot.claimable == "1"
    assert snapshot.vest_pool == "5000000"
    assert snapshot.vest_released == "1"
    assert snapshot.vest_claimed == "0"
    assert snapshot.vest_start == 1_700_000_000
    assert snapshot.animata_i_held_by_redeemer == 12

    assert pinned_calls() == [
             {aggregator(), aggregate(protocol_calls() ++ account_calls() ++ approval_calls()),
              latest()},
             {animata_i(), RedemptionAbi.encode_erc721("owner_of", [@token_id]), latest()}
           ]
  end

  test "NO_TOKEN_NO_OWNER_READ: a wallet without a token selection makes exactly one call" do
    assert {:ok, snapshot} = RpcClient.overview(@wallet, animata_i(), nil)

    assert snapshot.nft_approved == true
    assert snapshot.selected_collection == animata_i()
    assert snapshot.token_id == nil
    assert snapshot.nft_owner == nil
    assert snapshot.nft_owner_unavailable == false

    assert pinned_calls() == [
             {aggregator(), aggregate(protocol_calls() ++ account_calls() ++ approval_calls()),
              latest()}
           ]

    assert {:ok, snapshot} = RpcClient.overview(@wallet, nil, nil)

    assert snapshot.nft_approved == nil
    assert snapshot.selected_collection == nil
    assert snapshot.usdc_balance == "100"

    assert pinned_calls() == [
             {aggregator(), aggregate(protocol_calls() ++ account_calls()), latest()}
           ]
  end

  # Under the aggregator every sub-call is made by Multicall3, so a read about
  # an account that leaned on `msg.sender` would answer about the aggregator.
  test "EXPLICIT_ARGUMENTS: every account sub-call names the wallet in its own calldata" do
    assert {:ok, _snapshot} = overview()
    wallet_word = String.trim_leading(@wallet, "0x")

    for {_target, data} <- account_calls() ++ approval_calls() do
      assert String.contains?(data, wallet_word)
    end
  end

  test "OWNER_UNAVAILABLE: an unreadable owner preserves all other current facts" do
    Stub.put(%{owner_of: :unavailable})
    assert {:ok, snapshot} = overview()
    assert snapshot.nft_owner_unavailable
    assert snapshot.nft_owner == nil
    assert snapshot.usdc_balance_raw == "100000000"
    assert snapshot.usdc_allowance_raw == "80000000"
    assert snapshot.claimable_raw == Integer.to_string(@claimable)
  end

  test "OWNER_MISMATCH: a readable different owner remains a known chain fact" do
    Stub.put(%{owner: @other})
    assert {:ok, %{nft_owner: @other, nft_owner_unavailable: false}} = overview()
  end

  test "CONSTANTS_MISMATCH: a contract disagreeing with the manifest refuses the whole reading" do
    Stub.put(%{price: 1})
    assert {:error, :contract_constants_mismatch} = RpcClient.overview(nil, nil, nil)

    Stub.put(%{price: nil, animata_i: @other})
    assert {:error, :contract_constants_mismatch} = overview()
  end

  test "NON_CANONICAL_BLOCK: a block that moved fails the read instead of answering it" do
    Stub.put(%{canonical_block_hash: "0x" <> String.duplicate("9d", 32)})

    assert {:error, :chain_unavailable} = RpcClient.overview(nil, nil, nil)
    assert {:error, :chain_unavailable} = overview()
  end

  test "REVERTING_SUB_CALL: one refused sub-call makes the whole reading unavailable" do
    Application.put_env(:ash_platform, :redemption_http_client, Stub.UnsupportedCall)

    assert {:error, :chain_unavailable} = RpcClient.overview(nil, nil, nil)
    assert {:error, :chain_unavailable} = overview()
  end

  test "AGGREGATOR_IDENTITY: an unrecognised aggregator refuses the reading before it is made" do
    Stub.put(%{code: Stub.runtime_code(Abi.multicall3_runtime_bytes() - 1)})
    assert {:error, :runtime_mismatch} = RpcClient.overview(nil, nil, nil)

    Stub.put(%{code: "0x"})
    assert {:error, :runtime_mismatch} = overview()
    assert pinned_calls() == []
  end

  test "IDENTITY_IS_PINNED: the aggregator is identified at the same block the reads use" do
    assert {:ok, _snapshot} = overview()

    assert_received {:rpc, "eth_getCode", [address, %{blockHash: hash, requireCanonical: true}]}

    assert String.downcase(address) == String.downcase(Abi.multicall3_address())
    assert hash == Stub.latest_hash()
  end

  test "UNAVAILABLE_CHAIN: malformed or wrong-chain facts fail closed" do
    for state <- [
          %{latest_block: :unavailable},
          %{latest_block: %{"number" => "0x20"}},
          %{latest_block: %{"number" => "0x20", "hash" => "0xnope"}},
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

  defp overview, do: RpcClient.overview(@wallet, animata_i(), @token_id)

  defp animata_i, do: normalized(RedemptionAbi.animata_i_address())
  defp normalized(address), do: Abi.normalize_address!(address)
  defp aggregator, do: Abi.multicall3_address()
  defp aggregate(calls), do: Abi.encode_aggregate3(calls)
  defp latest, do: %{blockHash: Stub.latest_hash(), requireCanonical: true}

  defp protocol_calls do
    redeemer = RedemptionAbi.redeemer_address()

    [
      {redeemer, RedemptionAbi.encode_read("animata_i")},
      {redeemer, RedemptionAbi.encode_read("animata_ii")},
      {redeemer, RedemptionAbi.encode_read("result_collection")},
      {redeemer, RedemptionAbi.encode_read("usdc")},
      {redeemer, RedemptionAbi.encode_read("regent")},
      {redeemer, RedemptionAbi.encode_read("usdc_price")},
      {redeemer, RedemptionAbi.encode_read("price")},
      {redeemer, RedemptionAbi.encode_read("regent_payout")},
      {redeemer, RedemptionAbi.encode_read("vest_duration")},
      {redeemer, RedemptionAbi.encode_read("max_source_token_id")},
      {RedemptionAbi.animata_i_address(), RedemptionAbi.encode_erc20("balance_of", [redeemer])},
      {RedemptionAbi.animata_ii_address(), RedemptionAbi.encode_erc20("balance_of", [redeemer])},
      {RedemptionAbi.result_collection_address(),
       RedemptionAbi.encode_erc20("balance_of", [redeemer])}
    ]
  end

  defp account_calls do
    redeemer = RedemptionAbi.redeemer_address()
    usdc = RedemptionAbi.usdc_address()

    [
      {usdc, RedemptionAbi.encode_erc20("balance_of", [@wallet])},
      {usdc, RedemptionAbi.encode_erc20("allowance", [@wallet, redeemer])},
      {redeemer, RedemptionAbi.encode_read("claimable", [@wallet])},
      {redeemer, RedemptionAbi.encode_read("vest", [@wallet])}
    ]
  end

  defp approval_calls do
    operator = RedemptionAbi.redeemer_address()
    [{animata_i(), RedemptionAbi.encode_erc721("is_approved_for_all", [@wallet, operator])}]
  end

  # Every block-pinned `eth_call` this test's reads made, in the order they
  # were made: a read that was not asked for fails here rather than passing
  # unnoticed.
  defp pinned_calls(calls \\ []) do
    receive do
      {:rpc, "eth_call", [%{to: to, data: data}, block]} ->
        pinned_calls([{to, data, block} | calls])

      {:rpc, _method, _params} ->
        pinned_calls(calls)
    after
      0 -> Enum.reverse(calls)
    end
  end

  # One aggregate is one `eth_call`, so the stub answers it by recognising
  # which reading the client asked for and returning one entry per sub-call.
  defp call("0x82ad56cb" <> _rest = data, state) do
    cond do
      data == aggregate(protocol_calls()) ->
        Stub.aggregate3_result(protocol_words(state))

      data == aggregate(protocol_calls() ++ account_calls()) ->
        Stub.aggregate3_result(protocol_words(state) ++ account_words(state))

      data == aggregate(protocol_calls() ++ account_calls() ++ approval_calls()) ->
        Stub.aggregate3_result(
          protocol_words(state) ++ account_words(state) ++ [approval_word(state)]
        )
    end
  end

  defp call("0x6352211e" <> _token, state), do: Map.get(state, :owner_of, address(state[:owner]))

  defp protocol_words(state) do
    [
      address(Map.get(state, :animata_i) || RedemptionAbi.animata_i_address()),
      address(RedemptionAbi.animata_ii_address()),
      address(RedemptionAbi.result_collection_address()),
      address(RedemptionAbi.usdc_address()),
      address(RedemptionAbi.regent_address()),
      Stub.uint(Map.get(state, :price) || @price),
      Stub.uint(@price),
      Stub.uint(@payout),
      Stub.uint(604_800),
      Stub.uint(999),
      Stub.uint(12),
      Stub.uint(13),
      Stub.uint(14)
    ]
  end

  defp account_words(_state) do
    [
      Stub.uint(100_000_000),
      Stub.uint(@price),
      Stub.uint(@claimable),
      "0x" <> Enum.map_join([@payout, @claimable, 0, 1_700_000_000], &Stub.hex_word/1)
    ]
  end

  defp approval_word(state), do: Stub.uint(if(Map.get(state, :approved, true), do: 1, else: 0))
  defp address(value), do: "0x" <> Stub.address_word(value)
end
