defmodule AshPlatformWeb.AutolaunchBidLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.BidFixture
  import Phoenix.LiveViewTest

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.TestAutolaunchBidChainClient, as: Chain

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @approval_hash "0x" <> String.duplicate("aa", 32)
  @panel "#autolaunch-bid"

  setup %{conn: conn} do
    install()

    account =
      Accounts.register_verified!("did:privy:bid-live", @wallet, [@wallet], actor: %System{})

    %{
      conn: init_test_session(conn, %{human_account_id: account.id}),
      auction: auction!("Bidder page auction")
    }
  end

  test "SIMPLE_PRODUCT_FORM: the compact form reviews an amount, a maximum price and an estimate",
       %{conn: conn, auction: auction} do
    view = mount_bidder(conn, auction)

    assert has_element?(view, "#{@panel}[phx-hook='AutolaunchBidWallet']")
    assert has_element?(view, ".bid-wallet dd", "100")

    view
    |> form("#autolaunch-bid-form", %{amount: "12.5", max_price: "3"})
    |> render_change()

    assert render(view) =~ "about 5 tokens"

    view |> element("#{@panel} button", "Max") |> render_click()
    assert has_element?(view, "#autolaunch-bid-amount[value='100']")

    view
    |> form("#autolaunch-bid-form", %{amount: "12.5", max_price: "3"})
    |> render_submit()

    review = render(view)
    assert review =~ "12.5 REGENT"
    assert review =~ "Allow REGENT to be spent"
    assert review =~ "Allow this auction to draw REGENT"
    assert review =~ "Place the bid"
    assert has_element?(view, "#autolaunch-bid-review button", "Confirm in wallet")

    # No calldata, contract vocabulary or internal workflow state reaches the page.
    for jargon <- ["0xa52c8728", "Permit2", "calldata", "submitBid", "prevTick", "envelope"] do
      refute review =~ jargon
    end
  end

  test "ACTIVE_WALLET_IS_THE_SIGNER: an unlinked selection exposes nothing and cannot review", %{
    conn: conn,
    auction: auction
  } do
    {:ok, view, _html} = live(conn, "/autolaunch/auctions/#{auction.id}")
    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => @other})

    assert render(view) =~ "Switch back to a wallet on this account"
    refute has_element?(view, "#autolaunch-bid-form")

    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => @wallet})
    assert has_element?(view, "#autolaunch-bid-form")
  end

  test "PRODUCTION_STAYS_CLOSED: the page says bidding is not open and asks for no wallet", %{
    conn: conn,
    auction: auction
  } do
    Application.delete_env(:ash_platform, :autolaunch_bid_chain_client)
    view = mount_bidder(conn, auction)

    assert render(view) =~ "Bidding is not open on this auction yet."
    refute render(view) =~ "Confirm in wallet"
  end

  test "ONE_SENDABLE_STEP: the browser is handed only the step the server just claimed", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)

    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id, steps: steps})
    assert Enum.map(steps, & &1["step"]) == ~w(token_approval permit2_approval bid)

    render_hook(element(view, @panel), "sign_bid_step", %{
      "action-id" => action_id,
      "address" => @wallet
    })

    assert_push_event(view, "autolaunch-bid:send", %{
      action_id: ^action_id,
      step: "token_approval"
    })

    assert render(view) =~ "In your wallet"
  end

  test "THE_SERVER_DECIDES_TRUTH: a reported hash is verified here and never by the browser", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    claim(view, action_id)
    Chain.put(%{outcomes: %{token_approval: %{outcome: :confirmed}}})

    render_hook(element(view, @panel), "bid_submitted", %{
      "action_id" => action_id,
      "transaction_hash" => @approval_hash
    })

    page = render(view)
    assert page =~ "Confirmed"
    assert page =~ "0xaaaaaa…aaaa"
    assert has_element?(view, ~s(#{@panel} li[data-step="permit2_approval"]), "Ready")
  end

  test "A_REJECTION_ENDS_THE_CLAIM: nothing is resent and the browser storage is cleared", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})
    claim(view, action_id)

    render_hook(element(view, @panel), "bid_wallet_rejected", %{
      "action_id" => action_id,
      "code" => 4001
    })

    assert render(view) =~ "Not sent"
    assert_push_event(view, "autolaunch-bid:operation", %{terminal: true})
  end

  test "RELOAD_RECOVERS_THE_ROW: a stale browser hint restores nothing", %{
    conn: conn,
    auction: auction
  } do
    {:ok, view, _html} = live(conn, "/autolaunch/auctions/#{auction.id}")
    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => @wallet})
    render_hook(element(view, @panel), "restore_bid_operation", %{})

    assert_push_event(view, "autolaunch-bid:cleared", %{})
    refute has_element?(view, "#autolaunch-bid-review")
  end

  test "EXIT_CLAIM_AND_REFUND_ARE_NOT_BUILT: the page offers no position controls", %{
    conn: conn,
    auction: auction
  } do
    page = conn |> mount_bidder(auction) |> render()

    for absent <- ["Review exit", "Review claim", "Review return", "Reclaim", "Refund"] do
      refute page =~ absent
    end
  end

  defp mount_bidder(conn, auction) do
    {:ok, view, _html} = live(conn, "/autolaunch/auctions/#{auction.id}")
    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => @wallet})
    view
  end

  defp reviewed(conn, auction) do
    view = mount_bidder(conn, auction)

    view
    |> form("#autolaunch-bid-form", %{amount: "12.5", max_price: "3"})
    |> render_submit()

    view
  end

  defp claim(view, action_id) do
    render_hook(element(view, @panel), "sign_bid_step", %{
      "action-id" => action_id,
      "address" => @wallet
    })
  end
end
