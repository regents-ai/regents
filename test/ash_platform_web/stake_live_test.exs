defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.System
  alias AshPlatform.WalletActions.StakeRedeemOperations

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @unlinked "0x3333333333333333333333333333333333333333"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_staking_approval_status)
      Application.delete_env(:ash_platform, :test_staking_confirmation_result)
      Application.delete_env(:ash_platform, :test_staking_balances)
      Application.delete_env(:ash_platform, :test_staking_signer)
      restore_env(:wallet_action_clock, previous_clock)
    end)

    :ok
  end

  test "anonymous visitors can see public staking truth but cannot prepare actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert html =~ "100 REGENT"
    assert html =~ "Connect your account"
    refute has_element?(view, "#regent-staking [phx-click=prepare_staking]")
  end

  # The account is signed in, but no wallet is active in Privy yet. Nothing
  # private is read and the account's stored primary wallet is never substituted.
  test "P1_ACTIVE_WALLET_ONLY: a signed-in account without an active wallet gets no position",
       %{conn: conn} do
    view = signed_in(conn, "stake-no-active")
    html = render_async(view)

    assert html =~ "100 REGENT"
    assert has_element?(view, ~s(.stake-actions button[data-stake-connect]), "Connect or switch")
    refute has_element?(view, "#staking-amount")
    refute has_element?(view, "#regent-staking [phx-click=prepare_staking]")
    refute html =~ "Your stake"

    # A Solana or disconnected selection reaches the server as no address at all
    # and lands in exactly the same state.
    render_hook(view, "staking_active_wallet", %{"address" => nil})
    refute has_element?(view, "#staking-amount")
  end

  # An address the verified account does not hold cannot name a private position,
  # and the page says which recovery is available instead of guessing a wallet.
  test "P2_MEMBERSHIP_PROVEN: an unlinked active wallet reads nothing private", %{conn: conn} do
    view = signed_in(conn, "stake-unlinked")
    render_async(view)

    render_hook(view, "staking_active_wallet", %{"address" => @unlinked})
    render_async(view)
    html = render_async(view)
    assert html =~ "not one of the wallets on your Regent account"
    assert html =~ "100 REGENT"
    refute html =~ "Your stake"
    refute has_element?(view, "#staking-amount")
    assert has_element?(view, ~s(.stake-actions button[data-stake-connect]))
  end

  test "a signed-in wallet reviews, explicitly signs, confirms and refreshes", %{conn: conn} do
    view = signed_in(conn, "stake-live")
    activate(view, @wallet)

    assert has_element?(view, "#staking-amount")
    assert render(view) =~ "5 REGENT"

    view
    |> form("#staking-amount-form", %{"amount" => "1"})
    |> render_change()

    review(view, "stake")

    assert has_element?(view, ".stake-review", "Stake REGENT")
    assert render(view) =~ "separate exact token approval"
    assert render(view) =~ "1 REGENT"
    assert render(view) =~ "0x1111…1111"
    action_id = prepared_action_id(render(view))

    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: nil
    })

    submit(view, action_id, "approval", @approval_hash)

    html = render_async(view)
    assert html =~ "REGENT approval confirmed"
    assert html =~ "Continue after approval"

    # The server verified the receipt and the exact allowance, so it invites the
    # browser to preflight the same wallet rather than asking for a reapproval.
    assert_push_event(view, "staking:continue", %{
      action_id: ^action_id,
      expected_signer: @wallet
    })

    assert html =~
             ~r/The approval transaction was\s+confirmed on Base, but we have not re-read the current REGENT allowance\./

    refute html =~ "The exact REGENT allowance remains onchain"

    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: @approval_hash
    })

    sign(view, action_id)
    refute_push_event(view, "staking:prepared", _)

    submit(view, action_id, "action", @tx_hash)

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert html =~ "5 REGENT"
    refute html =~ "Review before signing"
  end

  # The preflight is necessary input and never authority: a readiness event that
  # does not carry the reviewed signer claims nothing at all.
  test "P4_PREFLIGHT_IS_INPUT: a dispatch reported for another address claims nothing",
       %{conn: conn} do
    account = register("stake-preflight", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    render_hook(view, "sign_prepared_staking", %{"action-id" => action_id, "address" => @other})

    refute_push_event(view, "staking:prepared", _)
    assert render(view) =~ "This review belongs to a different wallet"
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :stake)

    # The same review, reported by the wallet that actually prepared it, still
    # goes through the full server revalidation before the wallet opens.
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{envelope: %{expected_signer: @wallet}})

    assert {:ok, %{state: :approval_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # A wallet switch is a new signer. The amount and the private position go, and
  # a review nobody dispatched is withdrawn rather than rebound.
  test "P3_SWITCH_CLEARS_UNDISPATCHED_WORK: an undispatched review is withdrawn on a switch",
       %{conn: conn} do
    account = register("stake-switch", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    assert render(view) =~ "Review before signing"

    activate(view, @other)

    html = render(view)
    refute html =~ "Review before signing"
    assert html =~ ~s(value="")
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  # The wallet that prepared a review is the wallet reporting itself active, so
  # nothing is withdrawn: the review comes back exactly as it was left.
  test "P3_MATCHING_SIGNER_SURVIVES: a prepared review for the active wallet is restored",
       %{conn: conn} do
    account = register("stake-restore-prepared", [@wallet])
    {:ok, envelope} = Staking.prepare_stake(@wallet, "1", leased(account.id))

    view = mount_stake(conn, account)
    activate(view, @wallet)

    assert render(view) =~ "Review before signing"
    action_id = envelope.action_id

    assert has_element?(view, ~s(button[data-stake-confirm="#{action_id}"]))

    assert {:ok, %{state: :prepared, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # A claimed dispatch may already be open in its own wallet, so switching never
  # closes it. It stays visible for recovery and offers the new wallet no way to
  # sign it.
  test "P3_CLAIMED_WORK_STAYS_WITH_ITS_SIGNER: a switch neither cancels nor rebinds a dispatch",
       %{conn: conn} do
    account = register("stake-claimed-switch", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)

    activate(view, @other)

    html = render(view)
    assert html =~ "This review belongs to another wallet"
    refute has_element?(view, "[data-stake-confirm]")

    assert {:ok, %{state: :approval_dispatched, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The outstanding dispatch still holds this account's one Stake slot.
    assert render_click(view, "prepare_staking", %{"action" => "claim_usdc"}) =~
             "An earlier staking action is still outstanding"
  end

  # Fifty percent is the integer floor of the raw balance and Max is that
  # balance exactly, so a one-wei position can be moved in full but not halved.
  test "P5_EXACT_AMOUNTS: quick fills use exact raw balances and refuse a result of zero",
       %{conn: conn} do
    view = signed_in(conn, "stake-amounts")
    activate(view, @wallet)

    render_click(view, "fill_staking_amount", %{"portion" => "half"})
    assert render(view) =~ ~s(value="5")

    render_click(view, "fill_staking_amount", %{"portion" => "max"})
    assert render(view) =~ ~s(value="10")

    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    render_click(view, "fill_staking_amount", %{"portion" => "max"})
    assert render(view) =~ ~s(value="5")

    render_click(view, "fill_staking_amount", %{"portion" => "half"})
    assert render(view) =~ ~s(value="2.5")

    Application.put_env(:ash_platform, :test_staking_balances, %{token: "1", stake: "0"})
    render_click(view, "select_staking_action", %{"mode" => "stake"})
    render_click(view, "refresh_staking", %{})
    render_async(view)

    # One wei: half of it is nothing, so that shortcut is refused while Max
    # still names the exact wei available.
    assert has_element?(view, ~s(button[phx-value-portion="half"][disabled]))
    refute has_element?(view, ~s(button[phx-value-portion="max"][disabled]))
    render_click(view, "fill_staking_amount", %{"portion" => "max"})
    assert render(view) =~ ~s(value="0.000000000000000001")

    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    assert has_element?(view, ~s(button[phx-value-portion="half"][disabled]))
    assert has_element?(view, ~s(button[phx-value-portion="max"][disabled]))
  end

  # A claim of nothing is not an action. The controls say so, and the server
  # refuses the event even when it is sent anyway.
  test "P5_NO_ZERO_CLAIMS: zero USDC, REGENT and claim-and-restake controls are refused",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_balances, %{
      usdc_claimable: "0",
      regent_claimable: "0",
      regent_funded: "0"
    })

    view = signed_in(conn, "stake-zero-claims")
    activate(view, @wallet)

    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(view, ~s(button[phx-value-action="#{action}"][disabled]))
    end

    assert render_click(view, "prepare_staking", %{"action" => "claim_usdc"}) =~
             "no USDC rewards to claim"

    assert render_click(view, "prepare_staking", %{"action" => "claim_regent"}) =~
             "not enough to claim or reinvest"
  end

  # Refresh re-reads the active wallet. It is unavailable while a verification is
  # in flight, so it can never discard a submitted transaction.
  test "P5_REFRESH_NEVER_CANCELS_VERIFICATION: refresh is disabled while confirming",
       %{conn: conn} do
    account = register("stake-refresh", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_action(view, action_id)

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    assert has_element?(view, ~s(button[phx-click="refresh_staking"][disabled]))
    render_click(view, "refresh_staking", %{})

    # The refresh could not discard the submitted transaction: verification still
    # runs to completion and its hash is still the one on screen.
    assert render_async(view) =~ "Confirmed on Base"
    assert has_element?(view, ~s(.stake-submission a[href="https://basescan.org/tx/#{@tx_hash}"]))
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  test "a server-verified reverted main action resets the flow for a fresh prepare", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :reverted)

    view = signed_in(conn, "stake-reverted")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_action(view, action_id)

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "staking transaction reverted"
    refute html =~ "Submitted transaction"
    assert has_element?(view, ~s(button[phx-value-action="stake"]), "Review stake")
    assert_push_event(view, "staking:action-reverted", %{})
  end

  test "a verified approval can be abandoned without sending main and a fresh action can be prepared",
       %{conn: conn} do
    view = signed_in(conn, "stake-abandon")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)

    render_async(view)
    assert render(view) =~ "Continue after approval"
    refute render(view) =~ "Staking transaction:"

    view |> element(~s(button[phx-click="abandon_staking_approval"])) |> render_click()

    html = render(view)

    assert html =~
             "Staking was not sent. The approval transaction was confirmed on Base, but we have not re-read the current REGENT allowance. You can prepare a new action."

    refute html =~ "The exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})

    send(view.pid, {:staking_envelope_expired, action_id})
    refute render(view) =~ "approval review expired"

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    assert render(view) =~ "Review before signing"
  end

  test "an expired verified approval states that the current allowance was not reread", %{
    conn: conn
  } do
    view = signed_in(conn, "stake-expired-verified")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)

    assert render_async(view) =~ "REGENT approval confirmed"
    send(view.pid, {:staking_envelope_expired, action_id})

    html = render(view)

    assert html =~
             "This approval review expired. No staking transaction was sent. The approval transaction was confirmed on Base, but we have not re-read the current REGENT allowance."

    refute html =~ "The exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})
  end

  # Identity change: this used to say a pending approval "can be abandoned". The
  # database refuses to close a submitted-but-unverified approval, and the shell
  # used to clear the screen anyway, announcing a withdrawal that never happened.
  test "DATABASE_DECIDES_THE_RACE: a submitted-but-unverified approval is not withdrawn and says it is still pending",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_approval_status, :pending)

    account = register("stake-pending-abandon", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)

    render_async(view)
    view |> element(~s(button[phx-click="abandon_staking_approval"])) |> render_click()

    html = render(view)

    assert html =~
             "The approval transaction is still pending, so this review stays open. It may still confirm later — check it in your wallet or on Base before relying on the allowance state."

    assert shown_once?(html, short_hash(@approval_hash))
    refute_push_event(view, "staking:abandoned", _)

    assert {:ok, %{state: :approval_submitted, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The slot is still held, so no fresh review can replace it: the control is
    # disabled, and the server refuses the event even when it is sent anyway.
    assert has_element?(view, ~s(button[phx-value-action="stake"][disabled]))

    assert render_click(view, "prepare_staking", %{"action" => "stake"}) =~
             "Verify the submitted transaction before preparing another action."
  end

  # The database holds one active operation per account and capability, so a
  # dispatch already sent to the wallet refuses the next review. Naming the
  # amount and the wallet would be false.
  test "DIRECT_TRUTHFUL_UI: a review refused by an outstanding operation says so instead of blaming the amount",
       %{conn: conn} do
    view = signed_in(conn, "stake-outstanding")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")

    # The dispatch is claimed and the wallet is open. No hash exists yet, so the
    # shell holds no submission of its own and only the database knows.
    sign(view, prepared_action_id(render(view)))

    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    review(view, "unstake")

    html = render(view)
    assert html =~ "An earlier staking action is still outstanding"
    refute html =~ "Check the amount and wallet"
  end

  # Identity change: this used to end by preparing a fresh action, then said an
  # expired restored approval "clears the review". Both were wrong. A
  # submitted-but-unverified approval cannot be withdrawn, so it keeps the
  # account's one active Stake slot and the review stays on screen.
  test "DATABASE_DECIDES_THE_RACE: an expired restored approval keeps both the review and the outstanding approval",
       %{conn: conn} do
    expired_at = DateTime.utc_now() |> DateTime.add(-11, :minute)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> expired_at end)

    account = register("stake-expired", [@wallet])

    # The durable operation, not browser storage, carries the submitted approval
    # across the restart, so the restore is set up through the same domain the
    # shell uses.
    opts = leased(account.id)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)
    {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope.action_id, :approval, opts)

    {:ok, _bound} =
      Staking.bind_submitted_hash(envelope.action_id, :approval, @approval_hash, opts)

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end)

    view = mount_stake(conn, account)
    activate(view, @wallet)

    html = render(view)

    assert html =~
             "The approval transaction is still pending, so this review stays open. It may still confirm later — check it in your wallet or on Base before relying on the allowance state."

    assert shown_once?(html, short_hash(@approval_hash))
    refute_push_event(view, "staking:abandoned", _)

    # The approval was broadcast and has not been verified, so it cannot be
    # withdrawn: it still holds this account's one active Stake slot and no
    # fresh action can be prepared against it.
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    assert has_element?(view, ~s(button[phx-value-action="stake"][disabled]))

    assert render_click(view, "prepare_staking", %{"action" => "stake"}) =~
             "Verify the submitted transaction before preparing another action."

    assert {:ok, %{state: :approval_submitted, approval_transaction_hash: @approval_hash}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # The browser may report that the approval receipt reverted, but Base decides.
  # That verification writes a terminal fact, so it runs under the mounted lease
  # like every other protected write.
  test "CURRENT_AUTHORITY_OWNS_EVERY_WRITE: a wallet-reported approval revert is verified on Base and made terminal",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_approval_status, :pending)

    account = register("stake-approval-revert", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)
    assert render_async(view) =~ "not confirmed yet"

    Application.put_env(:ash_platform, :test_staking_approval_status, :reverted)

    render_hook(view, "staking_approval_reverted", %{
      "action_id" => action_id,
      "transaction_hash" => @approval_hash
    })

    assert render_async(view) =~ "The REGENT approval was reverted"
    assert_push_event(view, "staking:approval-reverted", %{})
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  test "an approval cannot be abandoned after the main transaction hash exists", %{conn: conn} do
    view = signed_in(conn, "stake-no-abandon")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_action(view, action_id)

    render_hook(view, "abandon_staking_approval", %{})

    assert render(view) =~ "Staking transaction:"
    refute_push_event(view, "staking:abandoned", _)
  end

  test "unknown or mismatched confirmations fail closed", %{conn: conn} do
    view = signed_in(conn, "stake-mismatch")
    activate(view, @wallet)

    render_hook(view, "confirm_staking", %{"action_id" => "other", "transaction_hash" => @tx_hash})

    assert render(view) =~ "does not match the reviewed action"
  end

  test "REJECTION_WRITES_NOTHING: a newline-padded submitted hash reaches neither the shell nor the row",
       %{conn: conn} do
    account = register("stake-malformed", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)

    submit(view, action_id, "approval", "0x" <> String.duplicate("a", 63) <> "\n")

    refute has_element?(view, ".stake-submission")

    assert {:ok, %{state: :approval_dispatched, approval_transaction_hash: nil}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  test "a late confirmation from a departed route is ignored" do
    route_spec = AshPlatformWeb.RouteCatalog.fetch!(:techtree, %{})

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        route_spec: route_spec,
        staking_confirmation_name: nil,
        staking_notice: nil,
        staking_signing?: false
      }
    }

    assert {:noreply, unchanged} =
             AshPlatformWeb.ShellLive.handle_async(
               {:staking_confirmation, "old"},
               {:ok, {:ok, %{staking: %{wallet_stake_balance: "999"}}}},
               socket
             )

    assert unchanged.assigns.staking_notice == nil
    refute Map.has_key?(unchanged.assigns, :staking)
  end

  test "U8_CURRENT_TRUTH_ONLY: the Stake introduction names only the token and the revenue rail",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert has_element?(view, ".stake-heading .stake-mono", "$REGENT")
    assert html =~ "Follow the shared revenue rail."
    refute html =~ "claim the rewards available to your connected wallet"
    refute html =~ "`$REGENT`"
  end

  test "U6_INLINE_SIGN_IN: the signed-out branch offers the existing sign-in bridge target", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/stake")
    render_async(view)

    assert has_element?(
             view,
             ~s(.stake-actions button[data-account-target="sign-in"]),
             "Sign in to stake"
           )
  end

  # A signed-in account whose reviewed wallet is not connected is told exactly
  # that, in fixed copy. The bridge has no add-wallet action, so no bridge
  # button appears, and no browser or provider text ever reaches the page.
  test "U1_BOUNDED_WALLET_COPY: a closed reason key renders fixed copy and offers no bridge button",
       %{conn: conn} do
    view = signed_in(conn, "stake-bounded")
    activate(view, @wallet)

    render_hook(view, "staking_wallet_failed", %{"reason" => "wallet_unavailable"})

    assert render(view) =~
             "The wallet in this review is not connected in this browser. Connect it to continue."

    refute has_element?(view, ~s([data-account-target="sign-in"]))

    render_hook(view, "staking_wallet_failed", %{"reason" => "signer_changed"})
    assert render(view) =~ "This review belongs to a different wallet than the one now active."

    render_hook(view, "staking_wallet_failed", %{"reason" => "unknown"})
    assert render(view) =~ "The wallet action did not complete."
  end

  # The exact rejection is the whole outcome: the neutral notice stays on screen
  # and the operation is closed. A rejection the server cannot bind to the
  # reviewed action never fabricates that copy.
  test "U2_NEUTRAL_REJECTION: the exact rejection leaves neutral copy that no failure overwrites",
       %{conn: conn} do
    account = register("stake-rejected", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    # A rejection the server cannot bind to a reviewed action is evidence of
    # nothing, so it never fabricates the neutral copy.
    render_hook(view, "staking_wallet_rejected", %{
      "action_id" => "other",
      "phase" => "action",
      "code" => 4001
    })

    refute render(view) =~ "Nothing was sent"

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)

    render_hook(view, "staking_wallet_rejected", %{
      "action_id" => action_id,
      "phase" => "approval",
      "code" => 4001
    })

    html = render(view)
    assert html =~ "You rejected the request in your wallet. Nothing was sent."
    refute html =~ "Review before signing"
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  test "U3_APPROVAL_PENDING_LOCK: every prepare control is disabled while an approval is pending",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_approval_status, :pending)

    view = signed_in(conn, "stake-locked")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")

    submit_approval(view, prepared_action_id(render(view)))
    render_async(view)
    assert_push_event(view, "staking:prepared", %{})

    for action <- ~w(stake claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(view, ~s(button[phx-value-action="#{action}"][disabled]))
    end

    for mode <- ~w(stake unstake) do
      assert has_element?(view, ~s(button[phx-value-mode="#{mode}"][disabled]))
    end

    # Verification stays available and never opens the wallet again.
    view |> element(~s(button[phx-click="retry_staking_approval_verification"])) |> render_click()
    render_async(view)
    refute_push_event(view, "staking:prepared", _)
  end

  test "U4_BASE_EXPLORER_TRUTH: each bound hash links to that exact transaction on Base", %{
    conn: conn
  } do
    view = signed_in(conn, "stake-explorer")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_action(view, action_id)

    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    assert has_element?(view, ~s(.stake-submission a[href="https://basescan.org/tx/#{@tx_hash}"]))

    # That link is the only place either hash is shown: the status notice names
    # what was submitted without repeating an unclickable copy of the hash.
    html = render(view)
    assert html =~ "Staking transaction submitted."
    assert shown_once?(html, short_hash(@approval_hash))
    assert shown_once?(html, short_hash(@tx_hash))

    # An unbound hash is refused before it can be rendered at all, so no
    # malformed transaction link can exist.
    submit(view, action_id, "action", "0xnot-a-hash")

    refute render(view) =~ "basescan.org/tx/0xnot-a-hash"
  end

  test "U5_EXPECTED_SIGNER_TRUTH: the review copies exactly the prepared signer", %{conn: conn} do
    view = signed_in(conn, "stake-signer")
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")

    assert has_element?(view, ".stake-review .stake-mono", "0x1111…1111")

    assert has_element?(
             view,
             ~s(.stake-review button[data-copy-signer="#{@wallet}"][aria-label="Copy the full wallet address"])
           )

    assert has_element?(
             view,
             ~s(.stake-review button[data-stake-confirm][data-stake-signer="#{@wallet}"]),
             "Confirm in wallet"
           )

    refute has_element?(view, ~s(.stake-review [phx-click="sign_prepared_staking"]))
  end

  defp register(suffix, wallets) do
    {:ok, account} =
      Accounts.register_verified("did:privy:#{suffix}", hd(wallets), wallets, actor: %System{})

    account
  end

  defp mount_stake(conn, account) do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    view
  end

  defp signed_in(conn, suffix), do: mount_stake(conn, register(suffix, [@wallet]))

  # The Stake hook reports which wallet Privy has active; every private read and
  # every write proves it again against the mounted lease.
  defp activate(view, wallet) do
    render_async(view)
    render_hook(view, "staking_active_wallet", %{"address" => wallet})
    render_async(view)
  end

  defp review(view, action),
    do: view |> element(~s(button[phx-value-action="#{action}"])) |> render_click()

  defp prepared_action_id(html) do
    [id] = Regex.run(~r/data-stake-confirm="([a-f0-9]+)"/, html, capture: :all_but_first)
    id
  end

  # The browser preflights the reviewed signer and the shell claims each dispatch
  # before the wallet opens, so a submitted hash only ever arrives for a phase the
  # database already granted.
  defp sign(view, action_id),
    do:
      render_hook(view, "sign_prepared_staking", %{
        "action-id" => action_id,
        "address" => @wallet
      })

  defp submit(view, action_id, phase, hash) do
    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => phase,
      "transaction_hash" => hash
    })
  end

  defp submit_approval(view, action_id) do
    sign(view, action_id)
    submit(view, action_id, "approval", @approval_hash)
  end

  defp submit_action(view, action_id) do
    submit_approval(view, action_id)
    render_async(view)
    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)
  end

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  defp shown_once?(html, text), do: length(String.split(html, text)) == 2

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
