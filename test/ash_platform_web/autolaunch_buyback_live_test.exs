defmodule AshPlatformWeb.AutolaunchBuybackLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @router "0x2222222222222222222222222222222222222222"
  @treasury "0x3333333333333333333333333333333333333333"
  @subject_id "0x" <> String.duplicate("42", 32)
  @hash "0x" <> String.duplicate("ab", 32)
  @now ~U[2026-07-31 12:00:00Z]

  defmodule ReferenceHttpStub do
    def get("https://oracle.invalid/buyback-live", _opts) do
      {:ok,
       %{
         status: 200,
         body: %{"data" => %{"attributes" => %{"price_usd" => "1"}}}
       }}
    end
  end

  defmodule ChainStub do
    @behaviour AshPlatform.Autolaunch.BuybackChainClient

    @impl true
    def confirm(_envelope, hash) do
      case Application.get_env(:ash_platform, :test_autolaunch_buyback_confirmation, :ok) do
        :ok -> {:ok, %{transaction_hash: hash, receipt_verified: true}}
        :pending -> {:error, :transaction_pending}
        :reverted -> {:error, :transaction_reverted}
      end
    end
  end

  setup do
    previous = %{
      reference_client:
        Application.get_env(:ash_platform, :autolaunch_buyback_reference_http_client),
      reference_url: Application.get_env(:ash_platform, :autolaunch_buyback_reference_url),
      chain_client: Application.get_env(:ash_platform, :autolaunch_buyback_chain_client),
      clock: Application.get_env(:ash_platform, :wallet_action_clock)
    }

    Application.put_env(
      :ash_platform,
      :autolaunch_buyback_reference_http_client,
      ReferenceHttpStub
    )

    Application.put_env(
      :ash_platform,
      :autolaunch_buyback_reference_url,
      "https://oracle.invalid/buyback-live"
    )

    Application.put_env(:ash_platform, :autolaunch_buyback_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> @now end)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_autolaunch_buyback_confirmation)
      restore(:autolaunch_buyback_reference_http_client, previous.reference_client)
      restore(:autolaunch_buyback_reference_url, previous.reference_url)
      restore(:autolaunch_buyback_chain_client, previous.chain_client)
      restore(:wallet_action_clock, previous.clock)
    end)

    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-buyback-live",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    subject =
      Autolaunch.import_subject!(
        @subject_id,
        "agent",
        8453,
        "0x4444444444444444444444444444444444444444",
        nil,
        nil,
        @treasury,
        nil,
        @wallet,
        1500,
        250,
        200,
        "0",
        "0",
        "11000000",
        actor: %System{}
      )

    subject = Autolaunch.set_subject_buyback_router!(subject, @router, actor: %System{})

    auction =
      Autolaunch.import_auction!(
        "Buyback review subject",
        nil,
        false,
        :graduated,
        DateTime.add(@now, -3_600, :second),
        actor: %System{}
      )

    token =
      Autolaunch.import_subject_token!(
        auction.id,
        subject.subject_id,
        "Buyback Subject",
        "BUY",
        nil,
        DateTime.add(@now, -3_600, :second),
        nil,
        actor: %System{}
      )

    token =
      Autolaunch.set_subject_token_price!(
        token,
        "1",
        "twap",
        @now,
        actor: %System{}
      )

    %{account: account, subject: subject, token: token}
  end

  test "subject page reviews the exact guarded settlement before opening the wallet", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)

    assert has_element?(
             view,
             "#subject-buyback-wallet[phx-hook='AutolaunchBuybackWallet']"
           )

    assert has_element?(view, "#subject-buyback-form", "Review settlement")

    view
    |> form("#subject-buyback-form",
      buyback: %{amount_usdc: "11", minimum_regent_output: "10"}
    )
    |> render_submit()

    assert has_element?(view, "#subject-buyback-review", "Settle treasury buyback")
    assert render(view) =~ @treasury
    assert render(view) =~ "0 ETH"

    view
    |> element("#subject-buyback-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-buyback:prepared", %{envelope: envelope})
    assert envelope.to == @router
    assert envelope.arguments.amount_usdc_atomic == "11000000"
    assert envelope.arguments.minimum_regent_output_atomic == "10000000000000000000"
  end

  test "every guard failure shows one plain market-paused message without internals", %{
    conn: conn,
    account: account,
    subject: subject,
    token: token
  } do
    Autolaunch.set_subject_token_price!(token, "1", "spot", @now, actor: %System{})
    {:ok, view, _html} = subject_live(conn, account, subject)

    view
    |> form("#subject-buyback-form",
      buyback: %{amount_usdc: "11", minimum_regent_output: "10"}
    )
    |> render_submit()

    html = render(view)
    assert html =~ "This market is temporarily paused. Try again after prices refresh."
    refute html =~ "twap_source_not_allowed"
    refute html =~ "buyback_market_paused"
    refute html =~ "spot"
  end

  test "a review with only 60 seconds left cannot open the wallet", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)
    prepare(view)

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(@now, 540, :second)
    end)

    view
    |> element("#subject-buyback-review button", "Confirm in wallet")
    |> render_click()

    assert render(view) =~ "wallet review expired"
    refute_push_event(view, "autolaunch-buyback:prepared", %{})
  end

  test "submitted hash survives expiry and refresh for read-only confirmation", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    {:ok, view, _html} = subject_live(conn, account, subject)
    prepare(view)

    view
    |> element("#subject-buyback-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-buyback:prepared", %{envelope: envelope})

    render_hook(view, "autolaunch_buyback_submitted", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash
    })

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(@now, 601, :second)
    end)

    {:ok, restored_view, _html} = subject_live(conn, account, subject)

    render_hook(restored_view, "restore_autolaunch_buyback_submission", %{
      "envelope" => envelope,
      "transaction_hash" => @hash
    })

    send(restored_view.pid, {:autolaunch_buyback_envelope_expired, envelope.action_id})
    assert has_element?(restored_view, "#subject-buyback-review", "Retry confirmation")

    render_hook(restored_view, "confirm_autolaunch_buyback", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash
    })

    render_async(restored_view)
    assert render(restored_view) =~ "Confirmed on Base"
    assert_push_event(restored_view, "autolaunch-buyback:confirmed", %{})
  end

  test "pending confirmation remains retryable and a reverted receipt clears the review", %{
    conn: conn,
    account: account,
    subject: subject
  } do
    Application.put_env(:ash_platform, :test_autolaunch_buyback_confirmation, :pending)
    {:ok, view, _html} = subject_live(conn, account, subject)
    prepare(view)

    view
    |> element("#subject-buyback-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "autolaunch-buyback:prepared", %{envelope: envelope})

    render_hook(view, "autolaunch_buyback_submitted", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash
    })

    render_hook(view, "confirm_autolaunch_buyback", %{
      "action_id" => envelope.action_id,
      "transaction_hash" => @hash
    })

    render_async(view)
    assert render(view) =~ "not confirmed yet"
    assert has_element?(view, "#subject-buyback-review", "Retry confirmation")

    Application.put_env(:ash_platform, :test_autolaunch_buyback_confirmation, :reverted)

    view
    |> element("#subject-buyback-review button", "Retry confirmation")
    |> render_click()

    render_async(view)
    assert render(view) =~ "buyback transaction reverted"
    refute has_element?(view, "#subject-buyback-review")
    assert_push_event(view, "autolaunch-buyback:reverted", %{})
  end

  defp subject_live(conn, account, subject) do
    conn
    |> init_test_session(%{human_account_id: account.id})
    |> live("/autolaunch/subjects/#{subject.subject_id}")
  end

  defp prepare(view) do
    view
    |> form("#subject-buyback-form",
      buyback: %{amount_usdc: "11", minimum_regent_output: "10"}
    )
    |> render_submit()
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
