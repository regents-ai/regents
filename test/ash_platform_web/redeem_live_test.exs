defmodule AshPlatformWeb.RedeemLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Redemption}
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @tx_hash "0x" <> String.duplicate("ab", 32)

  setup do
    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_redemption_confirmation_result)
      Application.delete_env(:ash_platform, :test_redemption_nft_approved)
      Application.delete_env(:ash_platform, :test_redemption_usdc_allowance)
      Application.delete_env(:ash_platform, :test_redemption_result_ready)
      Application.delete_env(:ash_platform, :test_redemption_refresh_error)
    end)

    :ok
  end

  test "public redemption facts render without wallet actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/redeem")
    html = render_async(view)

    assert html =~ "Redeem Animata"
    assert html =~ "80 USDC"
    assert html =~ "5,000,000 REGENT"
    assert html =~ "7 days"
    assert html =~ "Sign in with the wallet"
    refute has_element?(view, "[phx-click=prepare_redemption]")
  end

  test "signed-in user reviews one explicit action, submits, verifies and refreshes", %{
    conn: conn
  } do
    {:ok, account} =
      Accounts.register_verified("did:privy:redeem-live", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    render_async(view)
    assert render(view) =~ "Claimable REGENT"
    assert render(view) =~ "1 REGENT"

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "42"})
    |> render_change()

    html = render_async(view)
    assert html =~ "Token #42"

    view
    |> element(~s(button[phx-value-action="redeem"]), "Review redemption")
    |> render_click()

    html = render(view)
    assert html =~ "Review before signing"
    assert html =~ "Animata I · Token #42"
    assert html =~ "80 USDC"
    assert html =~ "0 ETH"
    action_id = prepared_action_id(html)

    view |> element(".redeem-review button", "Confirm in wallet") |> render_click()

    assert_push_event(view, "redemption:prepared", %{
      envelope: %{action: "redeem", expected_signer: @wallet}
    })

    submit(view, action_id)

    render_hook(view, "confirm_redemption", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert html =~ "Result token #1123"
    assert_push_event(view, "redemption:confirmed", %{})
  end

  test "selection cannot alter or discard a reviewed or submitted action", %{conn: conn} do
    Application.put_env(:ash_platform, :test_redemption_nft_approved, false)

    {:ok, account} =
      Accounts.register_verified("did:privy:redeem-locked", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    render_async(view)
    view |> element(~s(button[phx-value-action="approve_nft_collection"])) |> render_click()
    reviewed = render(view)
    assert reviewed =~ "Animata I collection"

    render_hook(view, "redemption_selection_changed", %{
      "collection" => "animata_ii",
      "token_id" => "99"
    })

    assert render(view) =~ "Animata I collection"
    refute render(view) =~ "Animata II collection"

    action_id = prepared_action_id(render(view))

    submit(view, action_id)

    render_hook(view, "cancel_redemption_review", %{})
    assert render(view) =~ short_hash(@tx_hash)
    assert render(view) =~ "Retry verification"
  end

  # Identity change: this used to say a failed refresh "stays terminal". A
  # receipt-verified revert is still terminal failure, but a failed reread is no
  # longer terminal anything, so the name now states only what remains true.
  test "RECEIPT_AND_REREAD_BOTH_REQUIRED: a server-verified revert is terminal failure", %{
    conn: conn
  } do
    {:ok, account} =
      Accounts.register_verified("did:privy:redeem-revert", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    render_async(view)
    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    action_id = prepared_action_id(render(view))
    Application.put_env(:ash_platform, :test_redemption_confirmation_result, :reverted)

    submit(view, action_id)

    render_hook(view, "confirm_redemption", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "transaction reverted"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "redemption:reverted", %{})
  end

  # Identity change: this used to assert a verified receipt "stays terminal" and
  # rendered "Confirmed on Base" while the reread had failed. That claim was
  # false, so the identity now asserts the opposite: without the authoritative
  # reread the action is not confirmed and stays open for verification retry.
  test "RECEIPT_AND_REREAD_BOTH_REQUIRED: a verified receipt is not success while the reread is missing",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_redemption_refresh_error, true)

    {:ok, account} =
      Accounts.register_verified("did:privy:redeem-refresh", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    render_async(view)
    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    action_id = prepared_action_id(render(view))

    submit(view, action_id)

    render_hook(view, "confirm_redemption", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    refute html =~ "Confirmed on Base"
    assert html =~ "could not be re-read"
    assert html =~ "not confirmed yet"

    # The action stays open for verification retry, and the browser is never
    # told the operation finished.
    assert html =~ "Retry verification"
    refute html =~ "Refresh redemption details"
    refute_push_event(view, "redemption:confirmed", _)
  end

  test "an unsigned review can be cancelled or expire, while a restored hash cannot be discarded",
       %{
         conn: conn
       } do
    {:ok, account} =
      Accounts.register_verified("did:privy:redeem-restore", @wallet, [@wallet], actor: %System{})

    session_conn = init_test_session(conn, %{human_account_id: account.id})
    {:ok, view, _html} = live(session_conn, "/redeem")
    render_async(view)

    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    first_id = prepared_action_id(render(view))
    view |> element(~s(button[phx-click="cancel_redemption_review"])) |> render_click()
    refute render(view) =~ "Review before signing"
    assert render(view) =~ "wallet review was cancelled"
    assert_push_event(view, "redemption:abandoned", %{})

    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    expiring_id = prepared_action_id(render(view))
    send(view.pid, {:redemption_envelope_expired, expiring_id})
    assert render(view) =~ "wallet review expired"
    refute render(view) =~ "Review before signing"

    # The durable operation, not browser storage, carries the submitted hash
    # across the restart, so the restore is set up through the same domain the
    # shell uses.
    opts = leased(account.id)
    {:ok, envelope} = Redemption.prepare_claim(@wallet, opts)
    {:ok, _claimed} = Redemption.claim_wallet_dispatch(envelope.action_id, opts)
    {:ok, _bound} = Redemption.bind_submitted_hash(envelope.action_id, @tx_hash, opts)

    {:ok, restored, _html} = live(session_conn, "/redeem")
    render_async(restored)
    render_hook(restored, "restore_redemption_submission", %{})

    assert render(restored) =~ short_hash(@tx_hash)
    assert render(restored) =~ "Retry verification"
    render_hook(restored, "cancel_redemption_review", %{})
    assert render(restored) =~ short_hash(@tx_hash)
    assert render(restored) =~ "Retry verification"
    refute first_id == expiring_id
  end

  defp prepared_action_id(html) do
    [id] = Regex.run(~r/phx-value-action-id="([a-f0-9]+)"/, html, capture: :all_but_first)
    id
  end

  # The shell claims the dispatch before the wallet opens, so a submitted hash
  # only ever arrives for a dispatch the database already granted.
  defp submit(view, action_id) do
    render_hook(view, "sign_prepared_redemption", %{"action-id" => action_id})

    render_hook(view, "redemption_submitted", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })
  end

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"
end
