defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.System
  alias AshPlatform.BaseRpcStub, as: Stub
  alias AshPlatform.WalletActions.{Abi, StakeRedeemOperations}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @unlinked "0x3333333333333333333333333333333333333333"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)

    on_exit(fn ->
      restore_env(:staking_chain_client, previous_client)
      Application.delete_env(:ash_platform, :test_staking_approval_status)
      Application.delete_env(:ash_platform, :test_staking_confirmation_result)
      Application.delete_env(:ash_platform, :test_staking_balances)
      Application.delete_env(:ash_platform, :test_staking_confirm_barrier)
      Application.delete_env(:ash_platform, :test_staking_overview_error)
      Application.delete_env(:ash_platform, :test_staking_read_watcher)
      Application.delete_env(:ash_platform, :test_staking_denominator)
      Application.delete_env(:ash_platform, :test_staking_paused)
      Application.delete_env(:ash_platform, :test_staking_allowance_current)
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

  # A signed-out visitor may still publish an active wallet. Nothing private is
  # read for it, and the page stays the public one with its sign-in path.
  test "PUBLIC_STAYS_PUBLIC: a signed-out wallet event never turns the page into an error", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/stake")
    render_async(view)

    render_hook(view, "staking_active_wallet", %{"address" => @wallet})
    html = render_async(view)

    assert html =~ "Sign in with the wallet"
    assert html =~ "100 REGENT"
    refute html =~ "unavailable right now"
    refute has_element?(view, "#regent-staking [phx-click=prepare_staking]")
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
             ~r/The approval was confirmed on\s+Base, and the allowance it granted stays in place until you change it\./

    refute html =~ "The exact REGENT allowance remains onchain"

    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: @approval_hash
    })

    sign(view, action_id)
    refute_push_event(view, "staking:prepared", _)

    submit(view, action_id, "action", @tx_hash)

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

    # Unstake spends a different balance, so the amount filled for Stake does
    # not carry over to it.
    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    assert render(view) =~ ~s(value="")

    render_click(view, "fill_staking_amount", %{"portion" => "max"})
    assert render(view) =~ ~s(value="5")

    render_click(view, "fill_staking_amount", %{"portion" => "half"})
    assert render(view) =~ ~s(value="2.5")

    Application.put_env(:ash_platform, :test_staking_balances, %{
      @wallet => %{token: "1", stake: "0"}
    })

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
      @wallet => %{usdc_claimable: "0", regent_claimable: "0", regent_funded: "0"}
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
             "Staking was not sent. The approval was confirmed on Base, and the allowance it granted stays in place until you change it. You can prepare a new action."

    refute html =~ "The exact REGENT allowance remains onchain"
    refute html =~ "Submitted transaction"
    assert_push_event(view, "staking:abandoned", %{})

    send(view.pid, {:staking_envelope_expired, action_id})
    refute render(view) =~ "approval review expired"

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    assert render(view) =~ "Review before signing"
  end

  test "an expired verified approval states that the granted allowance stays in place", %{
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
             "This approval review expired. No staking transaction was sent. The approval was confirmed on Base, and the allowance it granted stays in place until you change it."

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

    html = render_click(view, "prepare_staking", %{"action" => "unstake"})
    assert html =~ "An earlier staking action is still outstanding"
    refute html =~ "Check the amount and wallet"
  end

  # From the claim to the hash the review is the only thing that may be signed,
  # so every control that could replace or clear it is refused by the server as
  # well as disabled on screen. The claimed envelope survives them all, the
  # later hash still binds to it, and confirmation proceeds against it.
  test "P4_CLAIM_FREEZES_THE_REVIEW: late form events cannot replace a claimed envelope",
       %{conn: conn} do
    account = register("stake-claim-freeze", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})

    for control <- [
          ~s(#staking-amount[disabled]),
          ~s(button[phx-value-mode="unstake"][disabled]),
          ~s(button[phx-value-portion="half"][disabled]),
          ~s(button[phx-value-portion="max"][disabled]),
          ~s(button[phx-value-action="stake"][disabled])
        ] do
      assert has_element?(view, control)
    end

    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    render_click(view, "fill_staking_amount", %{"portion" => "max"})
    render_hook(view, "staking_amount_changed", %{"amount" => "9"})
    render_click(view, "prepare_staking", %{"action" => "stake"})

    # The reviewed envelope is untouched: same action, same amount, same signer.
    assert prepared_action_id(render(view)) == action_id
    assert render(view) =~ "1 REGENT"

    # The wallet reported something that is not the exact rejection, so the
    # request may still be open there: nothing is closed, nothing is resent and
    # the review stays exactly as locked as it was.
    render_hook(view, "staking_wallet_failed", %{"reason" => "unknown"})
    sign(view, action_id)
    refute_push_event(view, "staking:prepared", _)
    assert has_element?(view, ~s(#staking-amount[disabled]))
    assert prepared_action_id(render(view)) == action_id

    assert {:ok, %{state: :approval_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)

    submit(view, action_id, "approval", @approval_hash)
    render_async(view)
    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)

    assert render_async(view) =~ "Confirmed on Base"
    assert has_element?(view, ~s(.stake-submission a[href="https://basescan.org/tx/#{@tx_hash}"]))
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
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
    {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope, :approval, opts)

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
    assert has_element?(view, ~s(#staking-amount[disabled]))
    assert has_element?(view, ~s(button[phx-value-action="stake"][disabled]))

    assert render_click(view, "prepare_staking", %{"action" => "stake"}) =~
             "Verify the submitted transaction before preparing another action."

    assert {:ok, %{state: :approval_submitted, approval_transaction_hash: @approval_hash}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # The browser never decides that an approval reverted; the server's own read of
  # that hash does. It writes a terminal fact, so it runs under the mounted lease
  # like every other protected write.
  test "CURRENT_AUTHORITY_OWNS_EVERY_WRITE: an approval revert is verified on Base and made terminal",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_approval_status, :reverted)

    account = register("stake-approval-revert", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)

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

    # That link is the only place either hash is shown: the status notice says
    # what is happening without repeating an unclickable copy of the hash.
    html = render(view)
    assert html =~ "Confirming this transaction on Base"
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

  # Base being unreadable says nothing about whose wallet this is. The active
  # wallet, the review and the transaction already sent all survive it, no zero
  # or "not your wallet" is invented, and the retry recovers the position.
  test "P2_UNAVAILABLE_IS_NOT_A_VERDICT: a failed read keeps the wallet and the submitted hash",
       %{conn: conn} do
    account = register("stake-read-failure", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_approval(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})
    render_async(view)

    Application.put_env(:ash_platform, :test_staking_overview_error, :chain_unavailable)
    render_click(view, "refresh_staking", %{})
    html = render_async(view)

    assert html =~ "Staking details are unavailable right now"
    refute html =~ "not one of the wallets on your Regent account"
    refute html =~ "0 REGENT"

    # The transaction already sent is still on screen, on its own Base link, and
    # no balance or action is offered beside it.
    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    refute html =~ "Your stake"
    refute has_element?(view, ~s(button[phx-click="prepare_staking"]))

    # Nothing about the review moved: the verified approval is still the fact
    # the database holds for it.
    assert {:ok, %{state: :approval_verified, approval_transaction_hash: @approval_hash}} =
             StakeRedeemOperations.active(account.id, :stake)

    Application.delete_env(:ash_platform, :test_staking_overview_error)
    render_click(view, "refresh_staking", %{})
    render_async(view)

    assert has_element?(view, ".stake-metric dd", "5 REGENT")

    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    assert {:ok, %{state: :approval_verified}} = StakeRedeemOperations.active(account.id, :stake)
  end

  # A claimed phase owns this socket's review. Changing wallets takes the amount
  # and the position and nothing else, so the exact hash that comes back still
  # binds to the envelope that was claimed.
  test "P3_CLAIMED_WORK_TAKES_ITS_HASH_THROUGH_A_SWITCH: a late hash binds after the wallet changes",
       %{conn: conn} do
    account = register("stake-switch-hash", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})

    activate(view, @other)

    # The claimed review is still frozen, so nothing the form can send replaces it.
    render_hook(view, "staking_amount_changed", %{"amount" => "9"})
    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    render_click(view, "fill_staking_amount", %{"portion" => "max"})

    submit(view, action_id, "approval", @approval_hash)

    assert {:ok,
            %{
              action_id: ^action_id,
              state: :approval_submitted,
              approval_transaction_hash: @approval_hash
            }} = StakeRedeemOperations.active(account.id, :stake)

    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    render_async(view)
    refute_push_event(view, "staking:prepared", _)
  end

  # The same holds when the wallet goes away entirely: the claim is durable, so
  # its hash is still the one that binds when the wallet reports it.
  test "P3_CLAIMED_WORK_TAKES_ITS_HASH_THROUGH_A_DISCONNECT: a late hash binds after a disconnect",
       %{conn: conn} do
    account = register("stake-disconnect-hash", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})

    activate(view, nil)
    assert has_element?(view, ~s(button[data-stake-connect]))

    submit(view, action_id, "approval", @approval_hash)

    assert {:ok,
            %{
              action_id: ^action_id,
              state: :approval_submitted,
              approval_transaction_hash: @approval_hash
            }} = StakeRedeemOperations.active(account.id, :stake)

    # Reconnecting the same wallet finds the same review and the same hash.
    activate(view, @wallet)

    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    assert {:ok, %{action_id: ^action_id}} = StakeRedeemOperations.active(account.id, :stake)
  end

  # An active wallet the account does not hold removes itself and shows nothing
  # private, but it cannot end a request another wallet already opened: that
  # wallet's own late hash still binds, exactly once.
  test "P3_UNLINKED_WALLET_CANNOT_END_A_CLAIMED_REVIEW: the original wallet's late hash still binds",
       %{conn: conn} do
    account = register("stake-unlinked-claimed", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})

    # Privy moves to a wallet that is connected here but not on this account.
    render_hook(view, "staking_active_wallet", %{"address" => @unlinked})
    render_async(view)
    html = render_async(view)

    assert html =~ "not one of the wallets on your Regent account"
    assert html =~ "100 REGENT"
    refute html =~ "Your stake"
    refute has_element?(view, "#staking-amount")
    refute has_element?(view, "[data-stake-confirm]")

    # The wallet that opened the request reports its transaction.
    submit(view, action_id, "approval", @approval_hash)

    assert {:ok,
            %{
              action_id: ^action_id,
              state: :approval_submitted,
              approval_transaction_hash: @approval_hash
            }} = StakeRedeemOperations.active(account.id, :stake)

    render_async(view)
    render_hook(view, "staking_amount_changed", %{"amount" => "9"})
    render_click(view, "prepare_staking", %{"action" => "stake"})

    refute_push_event(view, "staking:prepared", _)
    assert {:ok, %{action_id: ^action_id}} = StakeRedeemOperations.active(account.id, :stake)
  end

  # A read that failed is not a claim of nothing. Preparation says Base could not
  # be read, and no durable operation is created on that evidence.
  test "P5_UNAVAILABLE_IS_NOT_ZERO: a failed read refuses claims without calling them empty",
       %{conn: conn} do
    account = register("stake-claim-unavailable", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    Application.put_env(:ash_platform, :test_staking_overview_error, :chain_unavailable)

    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent) do
      html = render_click(view, "prepare_staking", %{"action" => action})

      assert html =~ "Base could not be reached to check this wallet"
      refute html =~ "no USDC rewards to claim"
      refute html =~ "not enough to claim or reinvest"
      refute html =~ "Review before signing"
    end

    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  # A confirmation that finishes after the customer moved to another wallet
  # belongs to the wallet that signed it: it releases its own verification and
  # never paints its balances over the wallet now on screen.
  test "P3_CONFIRMATION_NEVER_OVERWRITES_ANOTHER_WALLET: a switch mid-verification keeps the new wallet's position",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_balances, %{
      @wallet => %{stake: "5000000000000000000"},
      @other => %{stake: "7000000000000000000"}
    })

    account = register("stake-confirm-switch", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_action(view, action_id)

    Application.put_env(:ash_platform, :test_staking_confirm_barrier, self())

    # Base is being read for the first wallet when the customer switches.
    assert_receive {:staking_confirming, confirmation}
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    render_hook(view, "staking_active_wallet", %{"address" => @other})

    # The second wallet's own position is read and delivered first, so the
    # confirmation is strictly the later result and would overwrite it if it
    # were allowed to.
    assert_receive {:staking_read, reader}
    monitor = Process.monitor(reader)
    assert_receive {:DOWN, ^monitor, :process, ^reader, _reason}
    send(confirmation, :release_staking_confirmation)

    html = render_async(view)

    assert has_element?(view, ".stake-metric dd", "7 REGENT")
    refute html =~ "5 REGENT"
    refute has_element?(view, ~s(button[phx-click="refresh_staking"][disabled]))
  end

  # The same result arriving after the wallet disappeared releases its
  # verification too, so the page is never left permanently verifying.
  test "P3_VERIFICATION_ALWAYS_RELEASES: a disconnect mid-verification leaves refresh usable",
       %{conn: conn} do
    account = register("stake-confirm-disconnect", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_action(view, action_id)

    Application.put_env(:ash_platform, :test_staking_confirm_barrier, self())

    assert_receive {:staking_confirming, confirmation}
    render_hook(view, "staking_active_wallet", %{"address" => nil})
    send(confirmation, :release_staking_confirmation)
    render_async(view)

    assert has_element?(view, ~s(button[data-stake-connect]))

    # Reconnecting the same wallet reads its position again, and refresh works.
    Application.delete_env(:ash_platform, :test_staking_confirm_barrier)
    activate(view, @wallet)

    assert has_element?(view, ".stake-metric dd", "5 REGENT")
    refute has_element?(view, ~s(button[phx-click="refresh_staking"][disabled]))
    render_click(view, "refresh_staking", %{})
    assert render_async(view) =~ "Your stake"
  end

  # The approval is already verified, so nothing needs approving again. A
  # preflight that cannot reach the active wallet sends no stake and leaves the
  # verified approval exactly as it is, with its manual retry.
  test "P4_CONTINUATION_FAILS_CLOSED: an unavailable wallet leaves the verified approval retryable",
       %{conn: conn} do
    account = register("stake-continue-retry", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_approval(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: nil})
    render_async(view)

    assert_push_event(view, "staking:continue", %{action_id: ^action_id})

    render_hook(view, "staking_wallet_failed", %{"reason" => "wallet_unavailable"})

    refute_push_event(view, "staking:prepared", _)
    assert {:ok, %{state: :approval_verified}} = StakeRedeemOperations.active(account.id, :stake)

    assert has_element?(
             view,
             ~s(button[data-stake-confirm="#{action_id}"]),
             "Continue after approval"
           )

    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{
      approval_transaction_hash: @approval_hash,
      envelope: %{action: "stake"}
    })

    assert {:ok, %{state: :action_dispatched, approval_transaction_hash: @approval_hash}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # `/stake` follows the wallet active in this browser and `/app` keeps reading
  # the account's stored primary wallet. Neither can be made to read the other's,
  # and coming back to `/stake` reads nothing private until the browser says
  # which wallet is active.
  test "P1_STAKE_ONLY_ACTIVE_WALLET: /stake reads the active wallet while /app keeps the stored primary",
       %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_balances, %{
      @wallet => %{stake: "5000000000000000000"},
      @other => %{stake: "7000000000000000000"}
    })

    account = register("stake-app-witness", [@wallet, @other])
    view = mount_stake(conn, account)
    activate(view, @other)

    assert has_element?(view, ".stake-metric dd", "7 REGENT")

    render_patch(view, "/app")
    html = render_async(view)

    assert html =~ "5 REGENT"
    refute html =~ "7 REGENT"

    # The browser may still publish its selection; `/app` does not read it.
    render_hook(view, "staking_active_wallet", %{"address" => @other})
    refute render(view) =~ "7 REGENT"

    render_patch(view, "/stake")
    refute render_async(view) =~ "7 REGENT"
    assert has_element?(view, ~s(button[data-stake-connect]))

    activate(view, @other)
    assert has_element?(view, ".stake-metric dd", "7 REGENT")
  end

  # Membership comes from the mounted session, not from Base, so an unreadable
  # chain can never stand between a customer and the wallet they may sign with.
  test "R4_MEMBERSHIP_IS_LOCAL: a dispatch is claimed while Base cannot be read", %{conn: conn} do
    account = register("stake-dispatch-no-base", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    Application.put_env(:ash_platform, :test_staking_overview_error, :chain_unavailable)
    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{envelope: %{expected_signer: @wallet}})
    refute render(view) =~ "Base could not be reached"

    assert {:ok, %{state: :approval_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  # The envelope is proven current again immediately before the durable claim,
  # so a review that expired while the page sat open opens no wallet at all.
  test "R1_EXPIRY_IS_PROVEN_BEFORE_THE_CLAIM: an expired review claims nothing", %{conn: conn} do
    account = register("stake-expired-claim", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))

    Application.put_env(:ash_platform, :wallet_action_clock, fn ->
      DateTime.add(DateTime.utc_now(), 11, :minute)
    end)

    sign(view, action_id)

    assert render(view) =~ "This review is no longer current. Prepare the action again."
    refute_push_event(view, "staking:prepared", _)
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :stake)
  end

  # The browser proved the wallet was never asked for anything, so the exact
  # claimed phase goes back to being signable instead of ending.
  test "R1_UNSTARTED_DISPATCH_IS_RETRYABLE: an approval that never reached the wallet is released",
       %{conn: conn} do
    account = register("stake-unstarted-approval", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{envelope: %{expected_signer: @wallet}})

    assert {:ok, %{state: :approval_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)

    not_started(view, action_id, "approval")

    assert render(view) =~ "Nothing was sent. You can try this action again."

    assert {:ok, %{state: :prepared, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The page is unlocked and the same review is the one still on screen.
    refute has_element?(view, ~s(#staking-amount[disabled]))
    assert has_element?(view, ~s(button[data-stake-confirm="#{action_id}"]))
    assert render(view) =~ "1 REGENT"

    # One retry claims exactly once.
    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{envelope: %{expected_signer: @wallet}})

    assert {:ok, %{state: :approval_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)

    sign(view, action_id)
    refute_push_event(view, "staking:prepared", _)
  end

  # The approval receipt and the exact allowance already held. Releasing an
  # unsent stake keeps them, so the retry sends the stake and never reapproves.
  test "R1_UNSTARTED_DISPATCH_IS_RETRYABLE: an unsent stake keeps its verified approval",
       %{conn: conn} do
    account = register("stake-unstarted-main", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_approval(view, action_id)
    render_async(view)

    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{approval_transaction_hash: @approval_hash})

    assert {:ok, %{state: :action_dispatched} = dispatched} =
             StakeRedeemOperations.active(account.id, :stake)

    not_started(view, action_id, "action")

    assert {:ok, %{state: :approval_verified, action_id: ^action_id} = released} =
             StakeRedeemOperations.active(account.id, :stake)

    assert approval_facts(released) == approval_facts(dispatched)
    assert is_nil(released.action_dispatched_at)

    assert has_element?(
             view,
             ~s(button[data-stake-confirm="#{action_id}"]),
             "Continue after approval"
           )

    sign(view, action_id)

    assert_push_event(view, "staking:prepared", %{
      approval_transaction_hash: @approval_hash,
      envelope: %{action: "stake"}
    })

    assert {:ok, %{state: :action_dispatched, approval_transaction_hash: @approval_hash}} =
             StakeRedeemOperations.active(account.id, :stake)
  end

  test "R1_UNSTARTED_DISPATCH_IS_RETRYABLE: an unsent action with no approval is released",
       %{conn: conn} do
    account = register("stake-unstarted-unstake", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    render_click(view, "select_staking_action", %{"mode" => "unstake"})
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "unstake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)

    assert {:ok, %{state: :action_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)

    not_started(view, action_id, "action")

    assert {:ok, %{state: :prepared, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)

    sign(view, action_id)
    assert_push_event(view, "staking:prepared", %{envelope: %{action: "unstake"}})

    assert {:ok, %{state: :action_dispatched}} =
             StakeRedeemOperations.active(account.id, :stake)

    # A released review is still only a review, so the next preparation replaces
    # it through the existing rule rather than being refused as outstanding.
    not_started(view, action_id, "action")
    view |> form("#staking-amount-form", %{"amount" => "2"}) |> render_change()
    review(view, "unstake")

    assert {:ok, %{state: :prepared, action_id: replacement}} =
             StakeRedeemOperations.active(account.id, :stake)

    refute replacement == action_id
  end

  # Only the socket that still holds this claim may say the wallet never saw it,
  # and only for the phase the review is actually on. Everything else refuses
  # without touching the row.
  test "R2_ONLY_THE_HOLDING_SOCKET_RELEASES: a second socket, a stale phase, a stale action and a duplicate all refuse",
       %{conn: conn} do
    account = register("stake-release-admission", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)

    # A restored second socket sees the same review but holds no claim of its own.
    second = mount_stake(conn, account)
    activate(second, @wallet)
    not_started(second, action_id, "approval")
    assert claimed_approval(account)

    # The holding socket, but for the phase this review is not on.
    not_started(view, action_id, "action")
    assert claimed_approval(account)

    # ...and for an action it never reviewed.
    not_started(
      view,
      "0000000000000000000000000000000000000000000000000000000000000000",
      "approval"
    )

    assert claimed_approval(account)

    not_started(view, action_id, "approval")
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :stake)

    # The latch went with the release, so a duplicate cannot start another one.
    sign(view, action_id)
    assert claimed_approval(account)
    not_started(view, action_id, "approval")
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :stake)
    not_started(view, action_id, "approval")
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(account.id, :stake)
  end

  # A release changes this socket's signing latch and its notice, and nothing
  # else: the envelope, the operation slot and the original expiry timer are
  # exactly as the claim left them.
  test "R3_RELEASE_MOVES_NOTHING_ELSE: the review keeps its slot and its original expiry timer",
       %{conn: conn} do
    account = register("stake-release-untouched", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    review(view, "stake")
    action_id = prepared_action_id(render(view))
    submit_approval(view, action_id)
    render_async(view)
    sign(view, action_id)

    not_started(view, action_id, "action")

    assert {:ok, %{state: :approval_verified, action_id: ^action_id}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The timer armed when this review was prepared is still the one that fires.
    send(view.pid, {:staking_envelope_expired, action_id})

    assert render(view) =~ "This approval review expired. No staking transaction was sent."
    assert_push_event(view, "staking:abandoned", %{})
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
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

  # A safe successful receipt that never recorded the action is terminal and is
  # never success. The hash stays on screen, the account's slot is freed, and
  # nothing is ever sent again on its own.
  test "FOUR_OUTCOMES: a contradicted receipt is terminal, non-success and frees the slot", %{
    conn: conn
  } do
    account = register("stake-unverified", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    review(view, "claim_usdc")
    action_id = prepared_action_id(render(view))
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :unverified)

    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)

    html = render_async(view)
    refute html =~ "Confirmed on Base"
    assert html =~ "without recording the action"
    assert html =~ short_hash(@tx_hash)
    assert_push_event(view, "staking:unverified", %{})
    refute_push_event(view, "staking:confirmed", _)

    # The slot is free, so a fresh review can be prepared straight away and
    # nothing was resent on the customer's behalf.
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
    review(view, "claim_usdc")
    assert render(view) =~ "Review before signing"
  end

  # Base's safe head trails the chain head, so a submitted transaction waits
  # rather than fails, and exactly one verification is outstanding at a time.
  test "ONE_RETRY_AT_A_TIME: a pending transaction waits and confirms on the same hash", %{
    conn: conn
  } do
    account = register("stake-pending", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    review(view, "claim_usdc")
    action_id = prepared_action_id(render(view))
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :pending)

    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)

    html = render_async(view)
    assert html =~ "Waiting for Base confirmation"
    assert html =~ short_hash(@tx_hash)

    assert {:ok, %{state: :action_submitted, action_transaction_hash: @tx_hash}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The same hash confirms once the safe head has advanced past it.
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :confirmed)
    send(view.pid, {:verification_retry, :stake, action_id})

    assert render_async(view) =~ "Confirmed on Base"
    assert_push_event(view, "staking:confirmed", %{})
  end

  # The whole connected path over a real Base transport: the wallet's hash is
  # bound, the read RPC has not seen it yet, and the page waits on that exact
  # hash instead of calling a transaction it cannot yet read unverifiable.
  test "PROPAGATION_LAG_IS_TRANSIENT: a just-broadcast hash waits and confirms on the same hash",
       %{conn: conn} do
    account = register("stake-propagation", [@wallet])
    Application.put_env(:ash_platform, :staking_chain_client, AshPlatform.Staking.RpcClient)
    Stub.install(:staking_http_client, &staking_call/2)
    Stub.put(%{transactions: %{}, receipts: %{}})

    view = mount_stake(conn, account)
    activate(view, @wallet)

    review(view, "claim_usdc")
    action_id = prepared_action_id(render(view))
    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)

    html = render_async(view)
    assert html =~ "Waiting for Base confirmation"
    assert html =~ short_hash(@tx_hash)
    refute html =~ "could not be verified from this session"

    assert {:ok, %{state: :action_submitted, action_transaction_hash: @tx_hash} = operation} =
             StakeRedeemOperations.active(account.id, :stake)

    # A load-balanced provider can answer with the receipt while its transaction
    # lookup still cannot. That identity is unavailable, not contradicted, so the
    # bound hash and its state survive and the same hash is read again.
    Stub.put(%{receipts: %{@tx_hash => Stub.receipt(@tx_hash, "0x10", [claim_usdc_log()])}})
    send(view.pid, {:verification_retry, :stake, action_id})
    assert render_async(view) =~ "Waiting for Base confirmation"

    assert {:ok, %{state: :action_submitted, action_transaction_hash: @tx_hash}} =
             StakeRedeemOperations.active(account.id, :stake)

    # The same hash, once the read RPC has caught up with the wallet.
    observe_transaction(operation.envelope)
    send(view.pid, {:verification_retry, :stake, action_id})

    assert render_async(view) =~ "Confirmed on Base"
    assert {:ok, nil} = StakeRedeemOperations.active(account.id, :stake)
  end

  # A verification that crashed says nothing about Base. It is not a pending
  # receipt, so it never re-arms the read; the page says what to do instead.
  @tag :capture_log
  test "ONE_RETRY_AT_A_TIME: a crashed verification stops rather than re-arming", %{conn: conn} do
    account = register("stake-crash", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    review(view, "claim_usdc")
    action_id = prepared_action_id(render(view))
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :crashes)

    sign(view, action_id)
    submit(view, action_id, "action", @tx_hash)

    html = render_async(view)
    assert html =~ "could not be verified from this session"
    refute html =~ "Waiting for Base confirmation"

    # The submitted hash and its state survive, and nothing is read again on its
    # own: only the customer's own retry asks Base anything further.
    assert html =~ short_hash(@tx_hash)

    assert {:ok, %{state: :action_submitted, action_transaction_hash: @tx_hash}} =
             StakeRedeemOperations.active(account.id, :stake)

    refute armed_verification?(view)
  end

  # Stale browser storage is told so exactly once rather than asking again on
  # every reload. No history copy is invented for work that already ended.
  test "STALE_STORAGE_CLEARS: a restore with no active operation clears the browser", %{
    conn: conn
  } do
    account = register("stake-stale", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    render_hook(view, "restore_staking_submission", %{})

    assert_push_event(view, "staking:abandoned", %{})
    refute render(view) =~ "Submitted transaction"
  end

  # The claim controls ask the domain the same question preparation asks of the
  # same snapshot, so the page cannot invite a compound the contract could not
  # take even though the reward itself is fully funded.
  test "AMOUNT_LIMITS: claim and restake is refused when the reward exceeds capacity", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "100000000000000000001")

    view = signed_in(conn, "stake-compound-capacity")
    activate(view, @wallet)

    assert has_element?(view, ~s(button[phx-value-action="claim_and_restake_regent"][disabled]))
    refute has_element?(view, ~s(button[phx-value-action="claim_regent"][disabled]))
    refute has_element?(view, ~s(button[phx-value-action="claim_usdc"][disabled]))
  end

  # The cap the deployed contract enforces is page truth, and the amount controls
  # are bounded by it exactly as preparation is.
  test "AMOUNT_LIMITS: remaining capacity is shown and bounds Max, 50% and the review", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "105000000000000000000")

    Application.put_env(:ash_platform, :test_staking_balances, %{
      @wallet => %{token: "10000000000000000000"}
    })

    account = register("stake-capacity", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    html = render(view)
    assert html =~ "Remaining capacity"
    assert html =~ "5 REGENT"

    # Capacity is below the wallet balance, so it is what Max may name.
    view |> element(~s(button[phx-value-portion="max"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="5"]))

    view |> element(~s(button[phx-value-portion="half"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="2.5"]))

    view |> form("#staking-amount-form", %{"amount" => "5.000000000000000001"}) |> render_change()
    html = render(view)
    assert html =~ "more REGENT than the staking contract can still take"
    assert has_element?(view, ~s(button[phx-value-action="stake"][disabled]))

    view |> form("#staking-amount-form", %{"amount" => "5"}) |> render_change()
    refute has_element?(view, ~s(button[phx-value-action="stake"][disabled]))
  end

  test "AMOUNT_LIMITS: an amount above the wallet or in the wrong language is refused inline", %{
    conn: conn
  } do
    account = register("stake-inline", [@wallet])
    view = mount_stake(conn, account)
    activate(view, @wallet)

    for {amount, expected} <- [
          {"10.000000000000000001", "more REGENT than this wallet holds"},
          {"1.0000000000000000001", "Enter an amount in REGENT above zero."},
          {"0", "Enter an amount in REGENT above zero."},
          {"nope", "Enter an amount in REGENT above zero."}
        ] do
      view |> form("#staking-amount-form", %{"amount" => amount}) |> render_change()
      html = render(view)
      assert html =~ expected, "#{amount} should be refused inline"
      assert has_element?(view, ~s(button[phx-value-action="stake"][disabled]))
    end

    view |> form("#staking-amount-form", %{"amount" => "10"}) |> render_change()
    refute has_element?(view, ~s(button[phx-value-action="stake"][disabled]))
  end

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

  # The browser proved this exact phase never crossed its transaction-send
  # boundary. It carries the action and the phase and nothing else.
  defp not_started(view, action_id, phase),
    do:
      render_hook(view, "staking_dispatch_not_started", %{
        "action_id" => action_id,
        "phase" => phase
      })

  defp claimed_approval(account) do
    {:ok, %{state: :approval_dispatched}} = StakeRedeemOperations.active(account.id, :stake)
    true
  end

  defp approval_facts(operation),
    do:
      Map.take(operation, [
        :approval_dispatched_at,
        :approval_transaction_hash,
        :approval_receipt_at
      ])

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

  # The one automatic verification this socket may hold, read from the socket
  # itself so a proof does not have to wait out a thirty-second interval.
  defp armed_verification?(view),
    do: not is_nil(:sys.get_state(view.pid).socket.assigns.staking_retry_ref)

  # The read RPC catches up with the wallet: this exact transaction, as the
  # operation's own stored envelope pinned it.
  defp observe_transaction(envelope) do
    Stub.put(%{
      transactions: %{
        @tx_hash => %{
          "hash" => @tx_hash,
          "from" => envelope["expected_signer"],
          "to" => envelope["to"],
          "input" => envelope["data"],
          "value" => "0x0"
        }
      }
    })
  end

  defp claim_usdc_log do
    %{
      "address" => Abi.staking_address(),
      "topics" => [Abi.event_topic(:usdc_reward_claimed), Stub.address_topic(@wallet)],
      "data" => "0x" <> Stub.hex_word(5) <> Stub.address_word(@wallet)
    }
  end

  # The pinned constants the overview proves before it accepts a snapshot; every
  # other read answers with a small positive balance.
  defp staking_call(data, _state) do
    cond do
      data == Abi.encode_read("stake_token") -> Stub.uint(word(Abi.stake_token_address()))
      data == Abi.encode_read("usdc") -> Stub.uint(word(Abi.usdc_address()))
      data == Abi.encode_read("paused") -> Stub.uint(0)
      data == Abi.encode_supply_denominator() -> Stub.uint(1_000)
      true -> Stub.uint(5)
    end
  end

  defp word(address), do: String.to_integer(String.trim_leading(address, "0x"), 16)

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  defp shown_once?(html, text), do: length(String.split(html, text)) == 2

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
