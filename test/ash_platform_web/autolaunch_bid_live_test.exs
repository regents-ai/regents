defmodule AshPlatformWeb.AutolaunchBidLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.BidFixture
  import Phoenix.LiveViewTest

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.TestAutolaunchBidChainClient, as: Chain

  @wallet "0x1111111111111111111111111111111111111111"
  @second "0x5555555555555555555555555555555555555555"
  @other "0x2222222222222222222222222222222222222222"
  @approval_hash "0x" <> String.duplicate("aa", 32)
  @bid_hash "0x" <> String.duplicate("cc", 32)
  @panel "#autolaunch-bid"

  setup %{conn: conn} do
    install()

    account =
      Accounts.register_verified!("did:privy:bid-live", @wallet, [@wallet, @second],
        actor: %System{}
      )

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

  test "ACTIVE_WALLET_IS_THE_SIGNER: no Ethereum wallet is an empty state, not a refusal", %{
    conn: conn,
    auction: auction
  } do
    view = mount_bidder(conn, auction)
    assert has_element?(view, "#autolaunch-bid-form")

    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => nil})

    assert render(view) =~ "Choose the wallet you want to bid from."
    refute has_element?(view, ".bid-notice")
    refute has_element?(view, "#autolaunch-bid-form")
  end

  test "ACTIVE_WALLET_IS_THE_SIGNER: switching wallets withdraws an undispatched review", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert has_element?(view, "#autolaunch-bid-review")

    render_hook(element(view, @panel), "bid_active_wallet", %{"address" => @second})

    assert_push_event(view, "autolaunch-bid:cleared", %{})
    refute has_element?(view, "#autolaunch-bid-review")
    assert has_element?(view, "#autolaunch-bid-form")
  end

  test "PRODUCTION_STAYS_CLOSED: the page says bidding is not open and offers no review", %{
    conn: conn,
    auction: auction
  } do
    Application.delete_env(:ash_platform, :autolaunch_bid_chain_client)
    view = mount_bidder(conn, auction)

    assert render(view) =~ "Bidding is not open on this auction yet."
    refute has_element?(view, "#autolaunch-bid-form")
    refute render(view) =~ "Confirm in wallet"
  end

  test "ONE_SENDABLE_STEP: the browser is handed only the step the server just claimed", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)

    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id, steps: steps})
    assert Enum.map(steps, & &1["step"]) == ~w(token_approval permit2_approval bid)

    claim(view, action_id)

    assert_push_event(view, "autolaunch-bid:send", %{
      action_id: ^action_id,
      step: "token_approval"
    })

    assert render(view) =~ "In your wallet"

    # The step is already claimed, so a repeated confirmation cannot become a
    # second wallet request from whatever this socket happens to be holding.
    claim(view, action_id)
    refute_push_event(view, "autolaunch-bid:send", %{})
  end

  test "THE_SERVER_DECIDES_TRUTH: a reported hash is verified here and never by the browser", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    claim(view, action_id)
    Chain.put(%{outcomes: %{token_approval: %{outcome: :confirmed}}})

    submit(view, action_id, "token_approval", @approval_hash)

    page = render(view)
    assert page =~ "Confirmed"
    assert page =~ "0xaaaaaa…aaaa"
    assert has_element?(view, ~s(#{@panel} li[data-step="permit2_approval"]), "Ready")
  end

  test "A_BOUND_HASH_IS_THE_TRUTH: a Base read that cannot answer keeps the sent transaction", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    claim(view, action_id)
    Chain.put(%{outcomes: %{token_approval: {:error, :chain_unavailable}}})

    submit(view, action_id, "token_approval", @approval_hash)

    page = render(view)
    assert page =~ "Sent"
    assert page =~ "0xaaaaaa…aaaa"
    assert has_element?(view, "#{@panel} button", "Check again")
    assert page =~ "Base could not be read just now."
    refute page =~ "Nothing was sent"

    # Nothing rolls back to the state before the hash bound.
    refute has_element?(view, ~s(#{@panel} li[data-step="token_approval"]), "Ready")
  end

  test "A_LOST_CALLBACK_REPLAYS: the exact durable hash is acknowledged and nothing rebinds", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    claim(view, action_id)
    Chain.put(%{outcomes: %{token_approval: %{outcome: :confirmed}}})
    submit(view, action_id, "token_approval", @approval_hash)

    assert_push_event(view, "autolaunch-bid:hash-durable", %{
      action_id: ^action_id,
      step: "token_approval",
      transaction_hash: @approval_hash
    })

    # A reload replays the callback it never got an answer for. The bid has
    # advanced, so the hash reaches only its own column, which already holds it.
    submit(view, action_id, "token_approval", @approval_hash)

    assert_push_event(view, "autolaunch-bid:hash-durable", %{transaction_hash: @approval_hash})
    assert has_element?(view, ~s(#{@panel} li[data-step="permit2_approval"]), "Ready")

    # A replay naming a step this bid is not on binds nowhere at all.
    submit(view, action_id, "bid", @bid_hash)

    assert render(view) =~ "not the step this bid is waiting for"
    refute render(view) =~ "0xcccccc…cccc"
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

  test "ONLY_A_PROVEN_MISS_SAYS_NOTHING_WAS_SENT: each reported reason gets its own copy", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})
    claim(view, action_id)

    # The wallet may already hold this transaction, so nothing here may invite a
    # retry or claim the send failed.
    failed(view, "send_unconfirmed")

    assert render(view) =~
             "Your wallet may have sent this transaction. Check your wallet activity before you start another bid."

    refute render(view) =~ "That did not go through"

    # The wallet was never reachable to be asked, which is the one reason that
    # proves nothing was sent.
    failed(view, "wallet_unavailable")

    assert render(view) =~
             "Open the wallet you are bidding from, then try again. Nothing was sent."

    failed(view, "unknown")

    page = render(view)
    assert page =~ "That did not go through. Try again in a moment."
    refute page =~ "Nothing was sent"
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

  # R2: a bid has two allowances before it, and each one is an independently
  # verified transaction of its own. All three appear once, in step order.
  test "EVERY_VERIFIED_STEP_IS_ONE_RESULT: both approvals and the bid are reported in step order",
       %{conn: conn, auction: auction} do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    permit2_hash = "0x" <> String.duplicate("bb", 32)

    claim(view, action_id)
    assert queued_results(view) == []

    Chain.put(%{outcomes: %{token_approval: %{outcome: :confirmed}}})
    submit(view, action_id, "token_approval", @approval_hash)

    claim(view, action_id)
    Chain.put(%{outcomes: %{permit2_approval: %{outcome: :confirmed}}})
    submit(view, action_id, "permit2_approval", permit2_hash)

    claim(view, action_id)
    Chain.put(%{outcomes: %{bid: %{outcome: :confirmed, onchain_bid_id: "7"}}})
    submit(view, action_id, "bid", @bid_hash)

    assert [token, permit2, bid] = queued_results(view)

    assert %{
             status: :confirmed,
             label: "Allow REGENT to be spent",
             message: "Confirmed on Base.",
             transaction_hash: @approval_hash
           } = token

    assert %{
             status: :confirmed,
             label: "Allow this auction to draw REGENT",
             transaction_hash: ^permit2_hash
           } = permit2

    assert %{
             status: :confirmed,
             label: "Place the bid",
             transaction_hash: @bid_hash,
             message: "Bid 7 is on Base. Your position appears once it is read back."
           } = bid

    # One dialog at a time, advancing through the queue as each is dismissed.
    for expected <- [token, permit2, bid] do
      assert view |> element("#transaction-result-portal") |> render() =~
               ~s(data-result-id="#{expected.id}")

      render_hook(view, "dismiss_transaction_result", %{"id" => expected.id})
    end

    assert queued_results(view) == []
  end

  test "ONLY_TERMINAL_OUTCOMES_ARE_RESULTS: a pending step and a rejection report nothing", %{
    conn: conn,
    auction: auction
  } do
    view = reviewed(conn, auction)
    assert_push_event(view, "autolaunch-bid:operation", %{action_id: action_id})

    claim(view, action_id)
    submit(view, action_id, "token_approval", @approval_hash)
    assert queued_results(view) == []

    render_hook(element(view, @panel), "bid_wallet_rejected", %{
      "action_id" => action_id,
      "code" => 4001
    })

    assert queued_results(view) == []
  end

  defp queued_results(view), do: :sys.get_state(view.pid).socket.assigns.transaction_results

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

  defp failed(view, reason),
    do: render_hook(element(view, @panel), "bid_wallet_failed", %{"reason" => reason})

  defp claim(view, action_id),
    do: render_hook(element(view, @panel), "sign_bid_step", %{"action-id" => action_id})

  defp submit(view, action_id, step, hash) do
    render_hook(element(view, @panel), "bid_submitted", %{
      "action_id" => action_id,
      "step" => step,
      "transaction_hash" => hash
    })
  end
end
