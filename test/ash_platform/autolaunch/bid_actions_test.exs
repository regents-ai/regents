defmodule AshPlatform.Autolaunch.BidActionsTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @paired "0x2222222222222222222222222222222222222222"
  @other "0x3333333333333333333333333333333333333333"
  @auction_address "0x4444444444444444444444444444444444444444"
  @quote_token "0x5555555555555555555555555555555555555555"
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)
  @q96 79_228_162_514_264_337_593_543_950_336

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.ChainClient

    @impl true
    def confirm(envelope, transaction_hash, approval_transaction_hash) do
      send(self_or_test(), {:confirm, envelope, transaction_hash, approval_transaction_hash})

      case Process.get(:autolaunch_confirmation, :success) do
        :success ->
          {:ok,
           %{
             transaction_hash: String.downcase(transaction_hash),
             receipt_verified: true
           }}

        reason ->
          {:error, reason}
      end
    end

    @impl true
    def approval_status(envelope, transaction_hash) do
      send(self_or_test(), {:approval_status, envelope, transaction_hash})
      {:ok, Process.get(:autolaunch_approval_status, :success)}
    end

    defp self_or_test, do: Process.get(:autolaunch_test_pid, self())
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :autolaunch_bid_chain_client)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    test_pid = self()

    Application.put_env(:ash_platform, :autolaunch_bid_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)
    Process.put(:autolaunch_test_pid, test_pid)

    on_exit(fn ->
      restore_env(:autolaunch_bid_chain_client, previous_client)
      restore_env(:wallet_action_clock, previous_clock)
      Process.delete(:autolaunch_confirmation)
      Process.delete(:autolaunch_approval_status)
    end)

    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-actions",
        @wallet,
        [@wallet, @paired],
        actor: %System{}
      )

    other_account =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-actions-other",
        @other,
        [@other],
        actor: %System{}
      )

    auction =
      Autolaunch.import_auction!(
        "Prepared action auction",
        nil,
        false,
        :active,
        ~U[2026-07-31 11:00:00Z],
        actor: %System{}
      )

    auction =
      Autolaunch.set_auction_bid_terms!(
        auction,
        @auction_address,
        @quote_token,
        "QUOTE",
        6,
        "2.5",
        actor: %System{}
      )

    %{
      actor: %Human{human_account_id: account.id},
      other_actor: %Human{human_account_id: other_account.id},
      auction: auction
    }
  end

  test "quote and bid preparation preserve decimal, Q96, approval and legacy calldata", %{
    actor: actor,
    auction: auction
  } do
    assert {:ok, quote} = Autolaunch.quote_auction_bid(auction.id, "12.5", "3")
    assert quote.amount == "12.5"
    assert quote.max_price == "3"
    assert quote.current_clearing_price == "2.5"
    assert quote.projected_clearing_price == "2.5"
    assert quote.estimated_tokens_if_end_now == "5"
    assert quote.status_band == "active"
    assert quote.warnings == []
    assert quote.quote_token == %{address: @quote_token, symbol: "QUOTE", decimals: 6}

    assert {:ok, envelope} =
             Autolaunch.prepare_auction_bid(auction.id, @wallet, "12.5", "3", actor: actor)

    assert envelope.resource == "autolaunch_auction"
    assert envelope.action == "submit_bid"
    assert envelope.to == @auction_address
    assert envelope.expected_signer == @wallet
    assert envelope.value == "0"
    assert envelope.arguments.amount_atomic == "12500000"
    assert envelope.arguments.max_price_q96 == Integer.to_string(3 * @q96)
    assert String.starts_with?(envelope.data, "0x140fe8ee")
    assert byte_size(envelope.data) == 10 + 5 * 64

    assert envelope.approval == %{
             token: @quote_token,
             spender: @auction_address,
             amount: "12500000",
             data:
               "0x095ea7b3" <>
                 String.pad_leading(String.trim_leading(@auction_address, "0x"), 64, "0") <>
                 String.pad_leading(
                   Integer.to_string(12_500_000, 16) |> String.downcase(),
                   64,
                   "0"
                 ),
             mode: "exact"
           }

    assert Envelope.valid?(envelope,
             resource: "autolaunch_auction",
             to: @auction_address,
             signer: @wallet,
             contract_name: "IContinuousClearingAuction",
             action: "submit_bid"
           )
  end

  test "decimal and signer boundaries fail closed", %{actor: actor, auction: auction} do
    for invalid <- ["0", "-1", "garbage", "1e3", "1.", ".5", ""] do
      assert {:error, :invalid_decimal} =
               Autolaunch.prepare_auction_bid(auction.id, @wallet, invalid, "3", actor: actor)

      assert {:error, :invalid_decimal} =
               Autolaunch.prepare_auction_bid(auction.id, @wallet, "1", invalid, actor: actor)
    end

    assert {:error, :invalid_amount_precision} =
             Autolaunch.prepare_auction_bid(
               auction.id,
               @wallet,
               "1.0000001",
               "3",
               actor: actor
             )

    assert {:ok, trailing_zeroes} =
             Autolaunch.prepare_auction_bid(
               auction.id,
               @wallet,
               "1.0000000",
               "3",
               actor: actor
             )

    assert trailing_zeroes.arguments.amount_atomic == "1000000"

    assert {:error, :wrong_signer} =
             Autolaunch.prepare_auction_bid(auction.id, @other, "1", "3", actor: actor)

    assert {:error, :invalid_address} =
             Autolaunch.prepare_auction_bid(auction.id, "not-a-wallet", "1", "3", actor: actor)

    assert {:error, :authentication_required} =
             Autolaunch.prepare_auction_bid(auction.id, @wallet, "1", "3")
  end

  test "Q96 preserves fractional prices and rejects values outside uint256", %{
    actor: actor,
    auction: auction
  } do
    assert {:ok, half} =
             Autolaunch.prepare_auction_bid(
               auction.id,
               @wallet,
               "1",
               "0.5",
               actor: actor
             )

    assert half.arguments.max_price_q96 == Integer.to_string(div(@q96, 2))

    assert {:error, :invalid_price} =
             Autolaunch.prepare_auction_bid(
               auction.id,
               @wallet,
               "1",
               "0.00000000000000000000000000000000000000000000000000000000000000000000000000000001",
               actor: actor
             )

    too_large = Integer.to_string(Integer.pow(2, 256))

    assert {:error, :invalid_decimal} =
             Autolaunch.prepare_auction_bid(
               auction.id,
               @wallet,
               "1",
               too_large,
               actor: actor
             )
  end

  test "post-bid actions require the stored owner, identity and eligible status", %{
    actor: actor,
    other_actor: other_actor,
    auction: auction
  } do
    returnable = bid!(auction, @paired, "returnable", "7")
    active = bid!(auction, @wallet, "active", "8")
    claimable = bid!(auction, @wallet, "claimable", "9")

    assert {:ok, returned} = Autolaunch.prepare_bid_return(returnable.bid_id, actor: actor)
    assert returned.expected_signer == @paired
    assert returned.to == @auction_address
    assert returned.data == "0x8e4deb17" <> String.pad_leading("7", 64, "0")

    assert {:ok, exited} = Autolaunch.prepare_bid_exit(active.bid_id, actor: actor)
    assert exited.data == "0x8e4deb17" <> String.pad_leading("8", 64, "0")

    assert {:ok, claimed} = Autolaunch.prepare_bid_claim(claimable.bid_id, actor: actor)
    assert claimed.data == "0x46e04a2f" <> String.pad_leading("9", 64, "0")

    assert {:error, _reason} =
             Autolaunch.prepare_bid_exit(active.bid_id, actor: other_actor)

    assert {:error, :bid_action_unavailable} =
             Autolaunch.prepare_bid_claim(active.bid_id, actor: actor)

    missing_identity =
      Autolaunch.import_bid_position!(
        "missing-chain-identity",
        auction.id,
        @wallet,
        "1",
        "3",
        "2.5",
        "0.4",
        "active",
        nil,
        nil,
        actor: %System{}
      )

    assert {:error, :invalid_address} =
             Autolaunch.prepare_bid_exit(missing_identity.bid_id, actor: actor)
  end

  test "confirmation is receipt-only, post-expiry, idempotent and bound to stored identity", %{
    actor: actor,
    auction: auction
  } do
    assert {:ok, envelope} =
             Autolaunch.prepare_auction_bid(auction.id, @wallet, "12.5", "3", actor: actor)

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:11:00Z] end)
    refute Envelope.valid?(envelope)
    assert Envelope.valid_for_confirmation?(envelope)

    for _ <- 1..2 do
      assert {:ok,
              %{
                transaction_hash: @hash,
                receipt_verified: true,
                auction: %{id: auction_id}
              }} =
               Autolaunch.confirm_bid_wallet_action(
                 envelope,
                 @hash,
                 @approval_hash,
                 actor: actor
               )

      assert auction_id == auction.id
      assert_receive {:confirm, ^envelope, @hash, @approval_hash}
    end

    for drifted <- [
          %{envelope | data: "0xdeadbeef"},
          %{envelope | expected_signer: @paired},
          %{envelope | to: @other},
          %{envelope | approval: %{envelope.approval | amount: "1"}}
        ] do
      assert {:error, _reason} =
               Autolaunch.confirm_bid_wallet_action(
                 drifted,
                 @hash,
                 @approval_hash,
                 actor: actor
               )
    end

    refute_receive {:confirm, _, _, _}
  end

  test "reverted, pending and approval receipts stay read-only", %{actor: actor, auction: auction} do
    assert {:ok, envelope} =
             Autolaunch.prepare_auction_bid(auction.id, @wallet, "1", "3", actor: actor)

    Process.put(:autolaunch_confirmation, :transaction_reverted)

    assert {:ok, %{receipt_verified: true, transaction_reverted: true}} =
             Autolaunch.confirm_bid_wallet_action(
               envelope,
               @hash,
               @approval_hash,
               actor: actor
             )

    Process.put(:autolaunch_confirmation, :transaction_pending)

    assert {:error, :transaction_pending} =
             Autolaunch.confirm_bid_wallet_action(
               envelope,
               @hash,
               @approval_hash,
               actor: actor
             )

    Process.put(:autolaunch_approval_status, :pending)

    assert {:ok, :pending} =
             Autolaunch.verify_bid_approval_submission(
               envelope,
               @approval_hash,
               actor: actor
             )

    assert_receive {:approval_status, ^envelope, @approval_hash}
  end

  defp bid!(auction, owner, status, onchain_bid_id) do
    bid =
      Autolaunch.import_bid_position!(
        "bid-#{status}-#{onchain_bid_id}",
        auction.id,
        owner,
        "12.5",
        "3",
        "2.5",
        "5",
        status,
        nil,
        nil,
        actor: %System{}
      )

    Autolaunch.set_bid_chain_identity!(
      bid,
      @auction_address,
      onchain_bid_id,
      actor: %System{}
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
