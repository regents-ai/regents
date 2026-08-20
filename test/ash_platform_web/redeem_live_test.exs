defmodule AshPlatformWeb.RedeemLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Redemption}
  alias AshPlatform.Actors.System
  alias AshPlatform.TestRedemptionChainClient
  alias AshPlatform.WalletActions.StakeRedeemOperations

  # The durable verdict and the page's current facts are separate reads. This
  # answers a confirmation exactly as the test client does while the page's own
  # snapshot is unavailable.
  defmodule UnreadableSnapshot do
    @moduledoc false
    @behaviour AshPlatform.Redemption.ChainClient

    @impl true
    def overview(_wallet, _collection, _token_id), do: {:error, :chain_unavailable}

    @impl true
    defdelegate confirm(envelope, transaction_hash), to: TestRedemptionChainClient

    @impl true
    defdelegate approval_current(envelope), to: TestRedemptionChainClient
  end

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @tx_hash "0x" <> String.duplicate("ab", 32)

  setup do
    on_exit(fn ->
      for key <- [
            :test_redemption_confirmation_result,
            :test_redemption_nft_approved,
            :test_redemption_usdc_allowance,
            :test_redemption_usdc_balance,
            :test_redemption_result_ready,
            :test_redemption_owner_unavailable,
            :test_redemption_nft_owner,
            :test_redemption_approvals_current
          ] do
        Application.delete_env(:ash_platform, key)
      end
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

  # Redeem follows the wallet Privy has selected, exactly as Stake does. Before
  # one is published the page shows public facts and one connect-or-switch path.
  test "ACTIVE_WALLET_DRIVES_REDEEM: private facts appear only for the published wallet", %{
    conn: conn
  } do
    account = register("redeem-active", [@wallet])
    view = mount_redeem(conn, account)
    render_async(view)

    assert has_element?(view, "button[data-redeem-connect]", "Connect or switch wallet")
    refute render(view) =~ "1 REGENT"

    activate(view, @wallet)
    assert render(view) =~ "Claimable REGENT"
    assert render(view) =~ "1 REGENT"

    # A wallet the account does not hold reads nothing private and says so.
    activate(view, @other)
    html = render_async(view)
    assert html =~ "not one of the wallets on your Regent account"
    assert has_element?(view, "button[data-redeem-connect]")

    # An absent or Solana selection is no wallet, never a substitute one.
    render_hook(view, "redemption_active_wallet", %{"address" => nil})
    render_async(view)
    assert has_element?(view, "button[data-redeem-connect]")
  end

  test "signed-in user reviews one explicit action, submits, verifies and refreshes", %{
    conn: conn
  } do
    account = register("redeem-live", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    view
    |> form("#redemption-selection", %{"collection" => "animata_i", "token_id" => "42"})
    |> render_change()

    html = render_async(view)
    assert html =~ "Token #42"
    assert html =~ "Redeem this Animata"

    next_step(view)

    html = render(view)
    assert html =~ "Review before signing"
    assert html =~ "Animata I · Token #42"
    assert html =~ "80 USDC"
    assert html =~ "0 ETH"
    action_id = prepared_action_id(html)

    sign(view, action_id)

    assert_push_event(view, "redemption:prepared", %{
      envelope: %{action: "redeem", expected_signer: @wallet}
    })

    submit(view, action_id)

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert html =~ "Redeemed for Regents Club token #1123"
    assert_push_event(view, "redemption:confirmed", %{})
  end

  # One clear next step at a time, in the order the redemption requires it.
  test "NEXT_STEP_IS_ONE_STEP: selection, then the one approval still missing, then Redeem", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_redemption_nft_approved, false)
    Application.put_env(:ash_platform, :test_redemption_usdc_allowance, 0)

    account = register("redeem-next", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    assert render(view) =~ "Choose a collection and a token ID between 1 and 999."
    assert has_element?(view, ".redeem-next-step button[disabled]")

    select(view, "animata_i", "42")
    assert render(view) =~ "Approve the selected collection for the Animata redeemer."

    Application.put_env(:ash_platform, :test_redemption_nft_approved, true)
    select(view, "animata_i", "42")
    assert render(view) =~ "Approve exactly 80 USDC for the Animata redeemer."

    Application.put_env(:ash_platform, :test_redemption_usdc_allowance, 80_000_000)
    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 79_999_999)
    select(view, "animata_i", "42")
    assert render(view) =~ "This wallet needs at least 80 USDC."
    assert has_element?(view, ".redeem-next-step button[disabled]")

    Application.put_env(:ash_platform, :test_redemption_usdc_balance, 100_000_000)
    select(view, "animata_i", "42")
    assert render(view) =~ "Redeem this Animata"
    refute has_element?(view, ".redeem-next-step button[disabled]")
  end

  # Claim is account-wide and independent of the selection, and disabled at zero.
  test "NEXT_STEP_IS_ONE_STEP: Claim stands apart from the redemption step", %{conn: conn} do
    account = register("redeem-claim", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    refute has_element?(view, ~s(button[phx-value-action="claim"][disabled]))

    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    assert render(view) =~ "Claim unlocked REGENT"
  end

  # An owner that could not be read is neutral: the core facts stay on screen and
  # the page never claims the token is missing or owned by someone else.
  test "OWNER_UNAVAILABLE: an unreadable owner keeps the core facts and neutral copy", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_redemption_owner_unavailable, true)

    account = register("redeem-owner", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)
    select(view, "animata_i", "42")

    html = render(view)
    assert html =~ "Unable to verify this NFT. Check the collection and token ID."
    assert html =~ "Claimable REGENT"
    assert html =~ "80 USDC"
    refute html =~ "does not own"
    assert has_element?(view, ".redeem-next-step button[disabled]")
  end

  test "OWNER_UNAVAILABLE: an exact owner mismatch is not-owned rather than unavailable", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_redemption_nft_owner, @other)

    account = register("redeem-not-owned", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)
    select(view, "animata_i", "42")

    html = render(view)
    assert html =~ "This wallet does not own the selected Animata token."
    refute html =~ "Unable to verify this NFT"
  end

  test "selection cannot alter or discard a reviewed or submitted action", %{conn: conn} do
    Application.put_env(:ash_platform, :test_redemption_nft_approved, false)

    account = register("redeem-locked", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)
    select(view, "animata_i", "42")

    next_step(view)
    assert render(view) =~ "Animata I collection"

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
  end

  test "FOUR_OUTCOMES: a verified revert is terminal failure", %{conn: conn} do
    account = register("redeem-revert", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    Application.put_env(:ash_platform, :test_redemption_confirmation_result, :reverted)
    submit(view, action_id)

    html = render_async(view)
    assert html =~ "transaction reverted"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "redemption:reverted", %{})
  end

  # A safe successful receipt whose logs never recorded the action is terminal
  # and is never success. The hash stays, the slot is freed, nothing is resent.
  test "FOUR_OUTCOMES: a contradicted receipt is terminal, non-success and frees the slot", %{
    conn: conn
  } do
    account = register("redeem-unverified", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    Application.put_env(:ash_platform, :test_redemption_confirmation_result, :unverified)
    submit(view, action_id)

    html = render_async(view)
    refute html =~ "Confirmed on Base"
    assert html =~ "without recording the action"
    assert html =~ short_hash(@tx_hash)
    assert_push_event(view, "redemption:unverified", %{})
    refute_push_event(view, "redemption:confirmed", _)

    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :redeem)
    assert render(view) =~ "Review REGENT claim"
  end

  # Not yet safe is not an outcome. The hash and its state survive, and exactly
  # one automatic verification is outstanding until the safe head advances.
  test "ONE_RETRY_AT_A_TIME: a pending transaction waits and confirms on the same hash", %{
    conn: conn
  } do
    account = register("redeem-pending", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    Application.put_env(:ash_platform, :test_redemption_confirmation_result, :pending)
    submit(view, action_id)

    assert render_async(view) =~ "Waiting for the submitted transaction to become safe on Base"

    Application.put_env(:ash_platform, :test_redemption_confirmation_result, :confirmed)
    send(view.pid, {:verification_retry, :redeem, action_id})

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert_push_event(view, "redemption:confirmed", %{})
  end

  # The exact event is the durable verdict and the page's current facts are a
  # separate read. When that read fails afterwards, the verdict, the exact hash
  # and the amount the event recorded stay on screen behind a read-only retry:
  # the terminal operation is never reopened and nothing is ever sent again.
  test "CONFIRMED_SURVIVES_A_FAILED_READ: the verdict, its hash and its result stay visible", %{
    conn: conn
  } do
    account = register("redeem-confirmed-unread", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    unreadable_snapshot()
    submit(view, action_id)

    # The confirmation settles, and then the page's own read fails.
    render_async(view)
    html = render_async(view)

    assert html =~ "Confirmed on Base"
    assert html =~ "Claimed 1 REGENT."
    assert html =~ short_hash(@tx_hash)
    assert html =~ "Redemption details are unavailable right now"

    assert has_element?(
             view,
             ~s(.redeem-status button[phx-click="refresh_redemption"]),
             "Try again"
           )

    # The terminal operation stayed terminal, and the failed read offers no
    # control that could open a wallet or send this transaction again.
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :redeem)
    refute has_element?(view, "[data-redeem-confirm]")
    refute has_element?(view, "[phx-click=prepare_redemption]")
  end

  # A reload recovers the durable operation, not a wallet step: the bound hash
  # comes back with exactly one read-only verification armed for it.
  test "RESTORE_IS_READ_ONLY: a restored hash re-arms one verification and opens no wallet", %{
    conn: conn
  } do
    account = register("redeem-restore-timer", [@wallet])
    session_conn = init_test_session(conn, %{human_account_id: account.id})

    opts = leased(account.id)
    {:ok, envelope} = Redemption.prepare_claim(@wallet, opts)
    {:ok, _claimed} = Redemption.claim_wallet_dispatch(envelope, opts)
    {:ok, _bound} = Redemption.bind_submitted_hash(envelope.action_id, @tx_hash, opts)

    {:ok, view, _html} = live(session_conn, "/redeem")
    activate(view, @wallet)

    first = armed_verification(view)
    assert is_integer(Process.read_timer(first))

    render_hook(view, "restore_redemption_submission", %{})
    second = armed_verification(view)

    # The earlier timer was cancelled rather than left to fire beside the new
    # one, so a restore can never leave two reads outstanding.
    assert Process.read_timer(first) == false
    assert is_integer(Process.read_timer(second))

    assert render(view) =~ short_hash(@tx_hash)
    refute has_element?(view, "[data-redeem-confirm]")

    # That timer only re-reads the hash the wallet already broadcast, so no
    # wallet was ever asked for anything across the restore or the read.
    send(view.pid, {:verification_retry, :redeem, envelope.action_id})

    assert render_async(view) =~ "Confirmed on Base"
    refute_push_event(view, "redemption:prepared", _)
  end

  # A signed-out visitor may still publish an active wallet. Nothing private is
  # read for it, and the page stays the public one with its sign-in path.
  test "PUBLIC_STAYS_PUBLIC: a signed-out wallet event never turns the page into an error", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/redeem")
    render_async(view)

    render_hook(view, "redemption_active_wallet", %{"address" => @wallet})
    html = render_async(view)

    assert html =~ "Sign in with the wallet"
    refute html =~ "unavailable right now"
    refute has_element?(view, "[phx-click=prepare_redemption]")
  end

  # Only a read that may answer differently later is retried. A refusal that
  # cannot change stops the automatic verification and says what to do instead.
  test "ONE_RETRY_AT_A_TIME: a permanent refusal stops the automatic verification", %{conn: conn} do
    account = register("redeem-permanent", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)

    # Base could not be read, which may answer differently in thirty seconds.
    Application.put_env(
      :ash_platform,
      :test_redemption_confirmation_result,
      {:error, :chain_unavailable}
    )

    submit(view, action_id)
    assert render_async(view) =~ "Waiting for the submitted transaction to become safe on Base"

    # A transaction identity a load-balanced provider has not returned yet is
    # unavailable evidence too, so the same hash waits rather than failing.
    Application.put_env(
      :ash_platform,
      :test_redemption_confirmation_result,
      {:error, :transaction_missing}
    )

    render_hook(view, "retry_redemption_confirmation", %{})
    assert render_async(view) =~ "Waiting for the submitted transaction to become safe on Base"

    # This envelope is refused for good, so nothing about it can change.
    Application.put_env(
      :ash_platform,
      :test_redemption_confirmation_result,
      {:error, :transaction_mismatch}
    )

    render_hook(view, "retry_redemption_confirmation", %{})
    html = render_async(view)

    assert html =~ "could not be verified from this session"
    refute html =~ "Waiting for the submitted transaction to become safe on Base"
    refute_push_event(view, "redemption:confirmed", _)
  end

  test "an unsigned review can be cancelled or expire, while a restored hash cannot be discarded",
       %{conn: conn} do
    account = register("redeem-restore", [@wallet])
    session_conn = init_test_session(conn, %{human_account_id: account.id})
    {:ok, view, _html} = live(session_conn, "/redeem")
    activate(view, @wallet)

    first_id = review_claim(view)
    view |> element(~s(button[phx-click="cancel_redemption_review"])) |> render_click()
    refute render(view) =~ "Review before signing"
    assert render(view) =~ "wallet review was cancelled"
    assert_push_event(view, "redemption:abandoned", %{})

    expiring_id = review_claim(view)
    send(view.pid, {:redemption_envelope_expired, expiring_id})
    assert render(view) =~ "wallet review expired"
    refute render(view) =~ "Review before signing"

    # The durable operation, not browser storage, carries the submitted hash
    # across the restart, so the restore is set up through the same domain the
    # shell uses.
    opts = leased(account.id)
    {:ok, envelope} = Redemption.prepare_claim(@wallet, opts)
    {:ok, _claimed} = Redemption.claim_wallet_dispatch(envelope, opts)
    {:ok, _bound} = Redemption.bind_submitted_hash(envelope.action_id, @tx_hash, opts)

    {:ok, restored, _html} = live(session_conn, "/redeem")
    activate(restored, @wallet)
    render_hook(restored, "restore_redemption_submission", %{})

    assert render(restored) =~ short_hash(@tx_hash)
    render_hook(restored, "cancel_redemption_review", %{})
    assert render(restored) =~ short_hash(@tx_hash)
    refute first_id == expiring_id
  end

  # Stale browser storage is told so exactly once rather than asking again on
  # every reload. No history copy is invented for work that already ended.
  test "STALE_STORAGE_CLEARS: a restore with no active operation clears the browser", %{
    conn: conn
  } do
    account = register("redeem-stale", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    render_hook(view, "restore_redemption_submission", %{})

    assert_push_event(view, "redemption:abandoned", %{})
    refute render(view) =~ "Submitted transaction"
  end

  test "DATABASE_DECIDES_THE_RACE: a claimed dispatch is not cancelled and the review stays visible",
       %{conn: conn} do
    account = register("redeem-claimed", [@wallet])
    session_conn = init_test_session(conn, %{human_account_id: account.id})
    {:ok, view, _html} = live(session_conn, "/redeem")
    activate(view, @wallet)

    # A second tab, mounted before anything was prepared, carries no review of
    # its own, so only the database knows one is outstanding.
    {:ok, other_tab, _html} = live(session_conn, "/redeem")
    activate(other_tab, @wallet)

    action_id = review_claim(view)

    # The wallet is open and no hash exists yet, so the shell holds no
    # submission of its own and only the database knows the dispatch was claimed.
    sign(view, action_id)
    render_hook(view, "cancel_redemption_review", %{})

    html = render(view)
    assert html =~ "Review before signing"
    assert html =~ "already went to your wallet"
    refute html =~ "wallet review was cancelled"
    refute_push_event(view, "redemption:abandoned", _)

    # The slot is still held, and the other tab's refusal says which fact holds
    # it rather than blaming the wallet or the selection.
    other_tab |> element(~s(button[phx-value-action="claim"])) |> render_click()
    html = render(other_tab)
    assert html =~ "An earlier redemption action is still outstanding"
    refute html =~ "Check the wallet and selection"
  end

  # The claim is durable before the wallet opens, so a preflight that proves the
  # wallet was never asked returns the same review rather than ending it.
  test "PRE_SEND_RELEASE: a dispatch the wallet never began is released for retry", %{conn: conn} do
    account = register("redeem-unstarted", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    sign(view, action_id)

    render_hook(view, "redemption_dispatch_not_started", %{"action_id" => action_id})

    html = render(view)
    assert html =~ "Nothing was sent. You can try this action again."
    assert html =~ "Review before signing"

    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :redeem)
  end

  test "REJECTION_WRITES_NOTHING: a newline-padded submitted hash reaches neither the shell nor the row",
       %{conn: conn} do
    account = register("redeem-malformed", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    submit(view, action_id, "0x" <> String.duplicate("a", 63) <> "\n")

    refute has_element?(view, ".redeem-submission")

    assert {:ok, %{state: :action_dispatched, action_transaction_hash: nil}} =
             StakeRedeemOperations.active(account.id, :redeem)
  end

  test "U6_INLINE_SIGN_IN: the signed-out branch offers the existing sign-in bridge target", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/redeem")
    render_async(view)

    assert has_element?(
             view,
             ~s(.redeem-actions button[data-account-target="sign-in"]),
             "Sign in to redeem"
           )
  end

  test "U1_BOUNDED_WALLET_COPY: a closed reason key renders fixed copy and offers no bridge button",
       %{conn: conn} do
    account = register("redeem-bounded", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    render_hook(view, "redemption_wallet_failed", %{"reason" => "wallet_unavailable"})

    assert render(view) =~
             "The wallet in this review is not connected in this browser. Connect it to continue."

    refute has_element?(view, ~s([data-account-target="sign-in"]))

    render_hook(view, "redemption_wallet_failed", %{"reason" => "unknown"})
    assert render(view) =~ "The wallet action did not complete."
  end

  test "U2_NEUTRAL_REJECTION: the exact rejection leaves neutral copy that no failure overwrites",
       %{conn: conn} do
    account = register("redeem-rejected", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    render_hook(view, "redemption_wallet_rejected", %{"action_id" => "other", "code" => 4001})
    refute render(view) =~ "Nothing was sent"

    action_id = review_claim(view)
    sign(view, action_id)

    render_hook(view, "redemption_wallet_rejected", %{"action_id" => action_id, "code" => 4001})

    html = render(view)
    assert html =~ "You rejected the request in your wallet. Nothing was sent."
    refute html =~ "Review before signing"
  end

  test "U4_BASE_EXPLORER_TRUTH: the submitted hash links to that exact transaction on Base", %{
    conn: conn
  } do
    account = register("redeem-explorer", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)

    action_id = review_claim(view)
    submit(view, action_id)

    assert has_element?(
             view,
             ~s(.redeem-submission a[href="https://basescan.org/tx/#{@tx_hash}"])
           )

    # That link is the only place the hash is shown: the status notice says what
    # is happening without repeating an unclickable copy of the hash.
    html = render(view)
    assert html =~ "Checking the submitted transaction on Base"
    assert shown_once?(html, short_hash(@tx_hash))

    # An unbound hash is refused before it can be rendered at all, so no
    # malformed transaction link can exist.
    render_hook(view, "redemption_submitted", %{
      "action_id" => action_id,
      "transaction_hash" => "0xnot-a-hash"
    })

    refute render(view) =~ "basescan.org/tx/0xnot-a-hash"
  end

  test "U5_EXPECTED_SIGNER_TRUTH: the review copies exactly the prepared signer", %{conn: conn} do
    account = register("redeem-signer", [@wallet])
    view = mount_redeem(conn, account)
    activate(view, @wallet)
    review_claim(view)

    assert has_element?(view, ".redeem-review .redeem-mono", "0x1111…1111")

    assert has_element?(
             view,
             ~s(.redeem-review button[data-copy-signer="#{@wallet}"][aria-label="Copy the full wallet address"])
           )
  end

  defp register(suffix, wallets) do
    {:ok, account} =
      Accounts.register_verified("did:privy:#{suffix}", hd(wallets), wallets, actor: %System{})

    account
  end

  defp mount_redeem(conn, account) do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/redeem")

    view
  end

  # The browser publishes the wallet Privy has selected; the server proves it.
  defp activate(view, wallet) do
    render_async(view)
    render_hook(view, "redemption_active_wallet", %{"address" => wallet})
    render_async(view)
  end

  defp select(view, collection, token_id) do
    view
    |> form("#redemption-selection", %{"collection" => collection, "token_id" => token_id})
    |> render_change()

    render_async(view)
  end

  defp next_step(view), do: view |> element(".redeem-next-step button") |> render_click()

  defp review_claim(view) do
    view |> element(~s(button[phx-value-action="claim"])) |> render_click()
    prepared_action_id(render(view))
  end

  defp prepared_action_id(html) do
    [id] = Regex.run(~r/data-redeem-confirm="([a-f0-9]+)"/, html, capture: :all_but_first)
    id
  end

  # The browser preflights the reviewed signer and the shell claims the dispatch
  # before the wallet opens, so a submitted hash only ever arrives for a dispatch
  # the database already granted.
  defp sign(view, action_id),
    do:
      render_hook(view, "sign_prepared_redemption", %{
        "action-id" => action_id,
        "address" => @wallet
      })

  defp submit(view, action_id, hash \\ @tx_hash) do
    sign(view, action_id)

    render_hook(view, "redemption_submitted", %{
      "action_id" => action_id,
      "transaction_hash" => hash
    })
  end

  # The page's own snapshot stops answering, while the confirmation this page
  # already asked for still settles exactly as it would have.
  defp unreadable_snapshot do
    previous = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, UnreadableSnapshot)
    on_exit(fn -> Application.put_env(:ash_platform, :redemption_chain_client, previous) end)
  end

  # The one automatic verification this socket may hold, read from the socket
  # itself so a proof does not have to wait out a thirty-second interval.
  defp armed_verification(view),
    do: :sys.get_state(view.pid).socket.assigns.redemption_retry_ref

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  defp shown_once?(html, text), do: length(String.split(html, text)) == 2
end
