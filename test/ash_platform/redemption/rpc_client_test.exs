defmodule AshPlatform.Redemption.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.Redemption.RpcClient
  alias AshPlatform.WalletActions.{Abi, Envelope, RedemptionAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @price 80_000_000
  @token_id 42

  setup do
    Stub.install(:redemption_http_client, &call/2)
    Stub.put(%{owner: @wallet})
    :ok
  end

  defp call(data, state), do: selector(String.slice(data, 0, 10), state)

  defp selector("0x5817e9d1", _state), do: address(RedemptionAbi.animata_i_address())
  defp selector("0x65d32f1e", _state), do: address(RedemptionAbi.animata_ii_address())
  defp selector("0xe54b3581", _state), do: address(RedemptionAbi.result_collection_address())
  defp selector("0x89a30271", _state), do: address(RedemptionAbi.usdc_address())
  defp selector("0x6d667d87", _state), do: address(RedemptionAbi.regent_address())
  defp selector("0xd8525aeb", _state), do: Stub.uint(@price)
  defp selector("0xa035b1fe", _state), do: Stub.uint(@price)
  defp selector("0xde12a91e", _state), do: Stub.uint(5_000_000_000_000_000_000_000_000)
  defp selector("0x6e6941c5", _state), do: Stub.uint(604_800)
  defp selector("0x17bac052", _state), do: Stub.uint(999)
  defp selector("0x70a08231", state), do: Stub.uint(Map.get(state, :usdc_balance, 100_000_000))
  defp selector("0xdd62ed3e", state), do: Stub.uint(Map.get(state, :allowance, @price))
  defp selector("0x402914f5", _state), do: Stub.uint(1_000_000_000_000_000_000)
  defp selector("0x474fc417", _state), do: "0x" <> String.duplicate(Stub.hex_word(1), 4)
  defp selector("0x6d970989", state), do: Stub.uint(Map.get(state, :result_token_id, 0))

  defp selector("0xe985e9c5", state),
    do: Stub.uint(if(Map.get(state, :approved, true), do: 1, else: 0))

  defp selector("0x6352211e", state), do: Map.get(state, :owner_of, address(state[:owner]))

  defp address(value), do: "0x" <> Stub.address_word(value)

  test "ONE_SAFE_BLOCK: every read of one overview is pinned to the same canonical block" do
    assert {:ok, snapshot} = overview()

    assert snapshot.block_number == 0x20
    assert snapshot.block_hash == Stub.safe_hash()
    assert snapshot.wallet_address == @wallet
    assert snapshot.nft_owner == @wallet
    refute snapshot.nft_owner_unavailable

    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    blocks = Stub.call_blocks()
    assert length(blocks) >= 15
    assert Enum.uniq(blocks) == [%{blockHash: Stub.safe_hash(), requireCanonical: true}]
  end

  test "ONE_SAFE_BLOCK: a missing, malformed or wrong-chain snapshot fails closed" do
    for {name, state} <- [
          {"no safe tag", %{safe_block: :unavailable}},
          {"header without a hash", %{safe_block: %{"number" => "0x20"}}},
          {"malformed block hash", %{safe_block: %{"number" => "0x20", "hash" => "0xnope"}}},
          {"wrong chain", %{chain_id: "0x1"}}
        ] do
      Stub.put(state)
      assert {:error, _unavailable} = overview(), "#{name} should fail closed"
    end
  end

  # The core account facts do not depend on the selected token, so an owner that
  # cannot be read leaves them intact. A transport failure and a token that does
  # not exist are indistinguishable here, and neither is reported as the other.
  test "OWNER_UNAVAILABLE: an unreadable owner preserves the core facts" do
    Stub.put(%{owner_of: :unavailable})

    assert {:ok, snapshot} = overview()

    assert snapshot.nft_owner_unavailable
    assert snapshot.nft_owner == nil
    assert snapshot.usdc_balance_raw == "100000000"
    assert snapshot.usdc_allowance_raw == "80000000"
    assert snapshot.claimable_raw == "1000000000000000000"
    assert snapshot.nft_approved == true
  end

  test "OWNER_UNAVAILABLE: an exact owner mismatch is a known owner, not an unavailable one" do
    Stub.put(%{owner: @other})

    assert {:ok, %{nft_owner: @other, nft_owner_unavailable: false}} = overview()
  end

  # Each action's own event, decoded against the deployed layout.
  test "EVENT_MATRIX: each action confirms on its exact event and nothing else" do
    collection = Abi.normalize_address!(RedemptionAbi.animata_i_address())
    redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())
    usdc = Abi.normalize_address!(RedemptionAbi.usdc_address())

    for {name, envelope, logs, expected} <- [
          {"collection approval", nft_approval_envelope(),
           [approval_for_all(collection, @wallet, redeemer, 1)], :confirmed},
          {"collection approval revoked", nft_approval_envelope(),
           [approval_for_all(collection, @wallet, redeemer, 0)], :unverified},
          {"collection approval for another operator", nft_approval_envelope(),
           [approval_for_all(collection, @wallet, @other, 1)], :unverified},
          {"collection approval from the wrong collection", nft_approval_envelope(),
           [approval_for_all(@other, @wallet, redeemer, 1)], :unverified},
          {"usdc approval", usdc_approval_envelope(), [approval(usdc, @wallet, redeemer, @price)],
           :confirmed},
          {"usdc approval of the wrong amount", usdc_approval_envelope(),
           [approval(usdc, @wallet, redeemer, @price - 1)], :unverified},
          {"usdc approval to another spender", usdc_approval_envelope(),
           [approval(usdc, @wallet, @other, @price)], :unverified},
          {"redeem", redeem_envelope(), [redeemed(@wallet, collection, @token_id, 1123)],
           :confirmed},
          {"redeem with no result token", redeem_envelope(),
           [redeemed(@wallet, collection, @token_id, 0)], :unverified},
          {"redeem of another token", redeem_envelope(),
           [redeemed(@wallet, collection, @token_id + 1, 1123)], :unverified},
          {"redeem of another collection", redeem_envelope(),
           [redeemed(@wallet, @other, @token_id, 1123)], :unverified},
          {"redeem by another account", redeem_envelope(),
           [redeemed(@other, collection, @token_id, 1123)], :unverified},
          {"redeem with no event", redeem_envelope(), [], :unverified},
          {"claim", claim_envelope(), [claimed(@wallet, 7)], :confirmed},
          {"claim of nothing", claim_envelope(), [claimed(@wallet, 0)], :unverified},
          {"claim for another account", claim_envelope(), [claimed(@other, 7)], :unverified},
          {"claim emitted twice", claim_envelope(), [claimed(@wallet, 7), claimed(@wallet, 7)],
           :unverified}
        ] do
      put_transaction(transaction(envelope))
      put_receipt(receipt("0x10", logs))

      assert {:ok, %{outcome: ^expected}} = RpcClient.confirm(envelope, @tx_hash),
             "#{name} should be #{expected}"
    end
  end

  # The redemption event carries no USDC amount, so its result token is reported
  # as a token and never as a value.
  test "EVENT_MATRIX: a confirmed redemption reports its exact result token" do
    collection = Abi.normalize_address!(RedemptionAbi.animata_i_address())
    put_transaction(transaction(redeem_envelope()))
    put_receipt(receipt("0x10", [redeemed(@wallet, collection, @token_id, 1123)]))

    assert {:ok, %{outcome: :confirmed, event: %{result_token_id: 1123}}} =
             RpcClient.confirm(redeem_envelope(), @tx_hash)
  end

  test "EVENT_MATRIX: a confirmed claim reports its exact amount" do
    put_transaction(transaction(claim_envelope()))
    put_receipt(receipt("0x10", [claimed(@wallet, 1_000_000_000_000_000_000)]))

    assert {:ok, %{outcome: :confirmed, event: %{claimed: "1"}}} =
             RpcClient.confirm(claim_envelope(), @tx_hash)
  end

  test "FOUR_OUTCOMES: pending, above-safe, reverted, confirmed and unverified" do
    envelope = claim_envelope()
    put_transaction(transaction(envelope))

    put_receipt(nil)
    assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x21", [claimed(@wallet, 7)]))
    assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x10", [], "0x0"))
    assert {:ok, %{outcome: :reverted}} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x10", [claimed(@wallet, 7)]))
    assert {:ok, %{outcome: :confirmed}} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt(receipt("0x10", []))
    assert {:ok, %{outcome: :unverified}} = RpcClient.confirm(envelope, @tx_hash)
  end

  # Canonical comes before status: a revert this transaction may still leave is
  # not a revert, exactly as a success it may still leave is not a success.
  test "FOUR_OUTCOMES: a receipt whose block is above safe or no longer canonical stays open" do
    envelope = claim_envelope()
    put_transaction(transaction(envelope))
    moved = %{"0x10" => %{"number" => "0x10", "hash" => "0x" <> String.duplicate("99", 32)}}

    for {name, status, logs} <- [{"success", "0x1", [claimed(@wallet, 7)]}, {"revert", "0x0", []}] do
      put_receipt(receipt("0x21", logs, status))
      Stub.put(%{blocks: %{}})

      assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash),
             "an above-safe #{name} should stay open"

      put_receipt(receipt("0x10", logs, status))
      Stub.put(%{blocks: moved})

      assert {:ok, %{outcome: :pending}} = RpcClient.confirm(envelope, @tx_hash),
             "a reorged #{name} should stay open"
    end
  end

  # Redeem spends both approvals, so both are read fresh at the dispatch that
  # spends them, and neither is required to remain afterwards. A collection that
  # is no longer approved is its own refusal and never a USDC failure.
  test "FRESH_APPROVAL: the redeem dispatch requires both approvals right now" do
    envelope = redeem_envelope()

    assert RpcClient.approval_current(envelope) == :ok
    assert_received {:rpc, "eth_getBlockByNumber", ["safe", false]}

    Stub.put(%{approved: false})
    assert RpcClient.approval_current(envelope) == {:error, :nft_approval_required}

    Stub.put(%{approved: true, allowance: @price - 1})
    assert RpcClient.approval_current(envelope) == {:error, :exact_usdc_approval_required}

    Stub.put(%{allowance: @price + 1})
    assert RpcClient.approval_current(envelope) == {:error, :exact_usdc_approval_required}

    # An approval action spends nothing, so it needs no current approval at all.
    assert RpcClient.approval_current(usdc_approval_envelope()) == :ok
  end

  test "transport logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :redemption_http_client, Stub.Timeout)

    log =
      capture_log(fn ->
        assert {:error, :chain_unavailable} = RpcClient.overview(nil, nil, nil)
      end)

    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp overview,
    do:
      RpcClient.overview(
        @wallet,
        Abi.normalize_address!(RedemptionAbi.animata_i_address()),
        @token_id
      )

  defp nft_approval_envelope do
    collection = Abi.normalize_address!(RedemptionAbi.animata_i_address())
    redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())

    Envelope.new(
      "approve_nft_collection",
      @wallet,
      RedemptionAbi.encode_erc721("set_approval_for_all", [redeemer, true]),
      resource: "animata_redemption",
      to: collection,
      contract_name: "Animata I",
      risk_copy: "Approve the collection.",
      arguments: %{collection: collection, operator: redeemer, approved: true}
    )
  end

  defp usdc_approval_envelope do
    redeemer = Abi.normalize_address!(RedemptionAbi.redeemer_address())

    Envelope.new(
      "approve_exact_usdc",
      @wallet,
      RedemptionAbi.encode_erc20("approve", [redeemer, @price]),
      resource: "animata_redemption",
      to: Abi.normalize_address!(RedemptionAbi.usdc_address()),
      contract_name: "USDC",
      risk_copy: "Approve exactly 80 USDC.",
      arguments: %{spender: redeemer, amount_atomic: Integer.to_string(@price), mode: "exact"}
    )
  end

  defp redeem_envelope do
    collection = Abi.normalize_address!(RedemptionAbi.animata_i_address())

    Envelope.new(
      "redeem",
      @wallet,
      RedemptionAbi.encode_action("redeem", [collection, @token_id]),
      resource: "animata_redemption",
      to: RedemptionAbi.redeemer_address(),
      contract_name: "AnimataRedeemer",
      risk_copy: "Redeem this Animata.",
      arguments: %{collection: collection, token_id: @token_id}
    )
  end

  defp claim_envelope do
    Envelope.new("claim", @wallet, RedemptionAbi.encode_action("claim", []),
      resource: "animata_redemption",
      to: RedemptionAbi.redeemer_address(),
      contract_name: "AnimataRedeemer",
      risk_copy: "Claim unlocked REGENT.",
      arguments: %{}
    )
  end

  defp transaction(envelope), do: Stub.transaction(@tx_hash, envelope)

  defp receipt(block_number, logs, status \\ "0x1"),
    do: Stub.receipt(@tx_hash, block_number, logs, status)

  defp approval_for_all(collection, owner, operator, approved),
    do: %{
      "address" => collection,
      "topics" => [
        RedemptionAbi.event_topic(:approval_for_all),
        Stub.address_topic(owner),
        Stub.address_topic(operator)
      ],
      "data" => Stub.uint(approved)
    }

  defp approval(token, owner, spender, value),
    do: %{
      "address" => token,
      "topics" => [
        Abi.event_topic(:approval),
        Stub.address_topic(owner),
        Stub.address_topic(spender)
      ],
      "data" => Stub.uint(value)
    }

  defp redeemed(user, source, token_id, result_token_id),
    do: %{
      "address" => Abi.normalize_address!(RedemptionAbi.redeemer_address()),
      "topics" => [
        RedemptionAbi.event_topic(:redeemed),
        Stub.address_topic(user),
        Stub.address_topic(source),
        Stub.uint(token_id)
      ],
      "data" => Stub.uint(result_token_id)
    }

  defp claimed(user, amount),
    do: %{
      "address" => Abi.normalize_address!(RedemptionAbi.redeemer_address()),
      "topics" => [RedemptionAbi.event_topic(:claimed), Stub.address_topic(user)],
      "data" => Stub.uint(amount)
    }

  defp put_receipt(receipt), do: Stub.put(%{receipts: %{@tx_hash => receipt}})
  defp put_transaction(transaction), do: Stub.put(%{transactions: %{@tx_hash => transaction}})
end
