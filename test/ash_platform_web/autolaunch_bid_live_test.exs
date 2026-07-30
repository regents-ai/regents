defmodule AshPlatformWeb.AutolaunchBidLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @auction_address "0x3333333333333333333333333333333333333333"
  @quote_token "0x4444444444444444444444444444444444444444"
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.ChainClient

    @impl true
    def confirm(_envelope, hash, _approval_hash),
      do: {:ok, %{transaction_hash: hash, receipt_verified: true}}

    @impl true
    def approval_status(_envelope, _hash),
      do: {:ok, Application.get_env(:ash_platform, :test_autolaunch_approval_status, :success)}
  end

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    previous_client = Application.get_env(:ash_platform, :autolaunch_bid_chain_client)

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)
    Application.put_env(:ash_platform, :autolaunch_bid_chain_client, ChainStub)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_autolaunch_approval_status)
      restore(:wallet_action_clock, previous_clock)
      restore(:autolaunch_bid_chain_client, previous_client)
    end)

    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-live",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    other =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-live-other",
        @other,
        [@other],
        actor: %System{}
      )

    auction =
      Autolaunch.import_auction!(
        "Wallet review auction",
        "Prepared bids stay in the wallet.",
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

    %{account: account, other: other, auction: auction}
  end

  test "auction page quotes and reviews an exact-approval bid before opening the wallet", %{
    conn: conn,
    account: account,
    auction: auction
  } do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    assert has_element?(view, "#auction-bid-wallet[phx-hook='AutolaunchBidWallet']")
    assert has_element?(view, "#auction-bid-form", "Review bid")

    view
    |> form("#auction-bid-form", bid: %{amount: "12.5", max_price: "3"})
    |> render_change()

    assert has_element?(view, "#auction-bid-quote", "Estimated tokens")
    assert render(view) =~ "5"

    view
    |> form("#auction-bid-form", bid: %{amount: "12.5", max_price: "3"})
    |> render_submit()

    assert has_element?(view, "#auction-bid-review", "Submit bid")
    assert render(view) =~ "exact quote-token approval"
    assert render(view) =~ "unlimited allowance"
    assert render(view) =~ "0 ETH"

    view
    |> element("#auction-bid-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-bid:prepared", %{envelope: envelope})
    assert envelope.approval.mode == "exact"
    assert envelope.approval.amount == "12500000"
  end

  test "reviews with 60 seconds remaining cannot open the wallet and confirmation is read-only",
       %{
         conn: conn,
         account: account,
         auction: auction
       } do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    view
    |> form("#auction-bid-form", bid: %{amount: "1", max_price: "3"})
    |> render_submit()

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:09:00Z] end)

    view
    |> element("#auction-bid-review button", "Confirm in wallet")
    |> render_click()

    assert render(view) =~ "wallet review expired"
    refute_push_event(view, "autolaunch-bid:prepared", %{})

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)

    view
    |> form("#auction-bid-form", bid: %{amount: "1", max_price: "3"})
    |> render_submit()

    view
    |> element("#auction-bid-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-bid:prepared", %{envelope: envelope})

    render_hook(view, "autolaunch_bid_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    render_hook(view, "autolaunch_bid_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "action",
      "transaction_hash" => @hash
    })

    render_hook(view, "confirm_autolaunch_bid", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash,
      "approval_transaction_hash" => @approval_hash
    })

    render_async(view)
    assert render(view) =~ "Confirmed on Base"
    assert_push_event(view, "autolaunch-bid:confirmed", %{})
  end

  test "submitted bid survives expiry across refresh and confirms at T+601", %{
    conn: conn,
    account: account,
    auction: auction
  } do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    view
    |> form("#auction-bid-form", bid: %{amount: "1", max_price: "3"})
    |> render_submit()

    view
    |> element("#auction-bid-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-bid:prepared", %{envelope: envelope})

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:09:59Z] end)

    render_hook(view, "autolaunch_bid_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    render_hook(view, "autolaunch_bid_submitted", %{
      "action_id" => envelope.action_id,
      "phase" => "action",
      "transaction_hash" => @hash
    })

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:10:01Z] end)

    {:ok, restored_view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    render_hook(restored_view, "restore_autolaunch_bid_submission", %{
      "envelope" => envelope,
      "approval_transaction_hash" => @approval_hash,
      "transaction_hash" => @hash
    })

    send(restored_view.pid, {:autolaunch_bid_envelope_expired, envelope.action_id})
    assert has_element?(restored_view, "#auction-bid-review", "Retry confirmation")

    render_hook(restored_view, "confirm_autolaunch_bid", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash,
      "approval_transaction_hash" => @approval_hash
    })

    render_async(restored_view)
    assert render(restored_view) =~ "Confirmed on Base"
    assert_push_event(restored_view, "autolaunch-bid:confirmed", %{})
  end

  test "restored approval can be verified, continued, or cancelled", %{
    conn: conn,
    account: account,
    auction: auction
  } do
    Application.put_env(:ash_platform, :test_autolaunch_approval_status, :pending)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    view
    |> form("#auction-bid-form", bid: %{amount: "1", max_price: "3"})
    |> render_submit()

    view
    |> element("#auction-bid-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-bid:prepared", %{envelope: envelope})

    {:ok, restored_view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    render_hook(restored_view, "restore_autolaunch_bid_submission", %{
      "envelope" => envelope,
      "approval_transaction_hash" => @approval_hash
    })

    send(restored_view.pid, {:autolaunch_bid_envelope_expired, envelope.action_id})

    assert has_element?(
             restored_view,
             ~s(button[phx-click="retry_autolaunch_bid_approval_verification"])
           )

    assert has_element?(restored_view, ~s(button[phx-click="cancel_autolaunch_bid_approval"]))

    Application.put_env(:ash_platform, :test_autolaunch_approval_status, :success)

    restored_view
    |> element(~s(button[phx-click="retry_autolaunch_bid_approval_verification"]))
    |> render_click()

    render_async(restored_view)
    assert has_element?(restored_view, "#auction-bid-review", "Continue to bid")

    restored_view
    |> element("#auction-bid-review button", "Continue to bid")
    |> render_click()

    assert_push_event(restored_view, "autolaunch-bid:prepared", %{
      envelope: %{action_id: action_id}
    })

    assert action_id == envelope.action_id

    restored_view
    |> element(~s(button[phx-click="cancel_autolaunch_bid_approval"]))
    |> render_click()

    assert render(restored_view) =~ "exact quote-token allowance remains onchain"
    assert_push_event(restored_view, "autolaunch-bid:abandoned", %{})
  end

  test "only owned stored positions expose their eligible review action", %{
    conn: conn,
    account: account,
    auction: auction,
    other: other
  } do
    own = bid!(auction, @wallet, "claimable", "9")
    _not_owned = bid!(auction, @other, "returnable", "10")

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/autolaunch/auctions/#{auction.id}")

    assert has_element?(view, "#auction-owned-bid-#{own.bid_id}", "Review claim")
    refute render(view) =~ "bid-returnable-10"

    view
    |> element(
      "#auction-owned-bid-#{own.bid_id} button[phx-value-action='claim_bid']",
      "Review claim"
    )
    |> render_click()

    assert has_element?(view, "#auction-bid-review", "Claim launch tokens")

    other_conn = init_test_session(conn, %{human_account_id: other.id})
    {:ok, other_view, _html} = live(other_conn, "/autolaunch/auctions/#{auction.id}")
    refute has_element?(other_view, "#auction-owned-bid-#{own.bid_id}")
  end

  defp bid!(auction, owner, status, onchain_bid_id) do
    bid =
      Autolaunch.import_bid_position!(
        "bid-#{status}-#{onchain_bid_id}",
        auction.id,
        owner,
        "1",
        "3",
        "2.5",
        "0.4",
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

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
