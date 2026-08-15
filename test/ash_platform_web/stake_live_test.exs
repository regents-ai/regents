defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.System
  alias AshPlatform.WalletActions.StakeRedeemOperations

  @wallet "0x1111111111111111111111111111111111111111"
  @tx_hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_staking_approval_status)
      Application.delete_env(:ash_platform, :test_staking_confirmation_result)
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

  test "a signed-in wallet reviews, explicitly signs, confirms and refreshes", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-live", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    assert has_element?(view, "#staking-amount")
    assert render(view) =~ "5 REGENT"

    view
    |> form("#staking-amount-form", %{"amount" => "1"})
    |> render_change()

    view
    |> element(~s(button[phx-value-action="stake"]), "Review stake")
    |> render_click()

    assert has_element?(view, ".stake-review", "Stake REGENT")
    assert render(view) =~ "separate exact token approval"
    assert render(view) =~ "1 REGENT"
    assert render(view) =~ "0x1111…1111"
    action_id = prepared_action_id(render(view))

    view
    |> element(".stake-review button", "Confirm in wallet")
    |> render_click()

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: nil
    })

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "approval",
      "transaction_hash" => @approval_hash
    })

    html = render_async(view)
    assert html =~ "REGENT approval confirmed"
    assert html =~ "Continue after approval"

    assert html =~
             ~r/The approval transaction was\s+confirmed on Base, but we have not re-read the current REGENT allowance\./

    refute html =~ "The exact REGENT allowance remains onchain"

    view
    |> element(".stake-submission button", "Continue after approval")
    |> render_click()

    assert_push_event(view, "staking:prepared", %{
      envelope: %{action: "stake", expected_signer: @wallet},
      approval_transaction_hash: @approval_hash
    })

    render_hook(view, "sign_prepared_staking", %{"action-id" => action_id})

    refute_push_event(view, "staking:prepared", _)

    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "action",
      "transaction_hash" => @tx_hash
    })

    render_hook(view, "confirm_staking", %{
      "action_id" => action_id,
      "transaction_hash" => @tx_hash
    })

    html = render_async(view)
    assert html =~ "Confirmed on Base"
    assert html =~ "5 REGENT"
    refute html =~ "Review before signing"
  end

  test "a server-verified reverted main action resets the flow for a fresh prepare", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_confirmation_result, :reverted)

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-reverted", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
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
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-abandon", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
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

    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    assert render(view) =~ "Review before signing"
  end

  test "an expired verified approval states that the current allowance was not reread", %{
    conn: conn
  } do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-expired-verified", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
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

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-pending-abandon", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    submit_approval(view, action_id)

    render_async(view)
    view |> element(~s(button[phx-click="abandon_staking_approval"])) |> render_click()

    html = render(view)
    assert html =~ "0xcdcdcd…cdcd"
    assert html =~ "this review stays open"
    assert html =~ "may still confirm later"
    assert html =~ "before relying on the allowance state"
    refute html =~ "exact REGENT allowance remains onchain"
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
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-outstanding", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()

    # The dispatch is claimed and the wallet is open. No hash exists yet, so the
    # shell holds no submission of its own and only the database knows.
    sign(view, prepared_action_id(render(view)))

    view |> element(~s(button[phx-value-action="unstake"]), "Review unstake") |> render_click()

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

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-expired", @wallet, [@wallet], actor: %System{})

    # The durable operation, not browser storage, carries the submitted approval
    # across the restart, so the restore is set up through the same domain the
    # shell uses.
    opts = leased(account.id)
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)
    {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope.action_id, :approval, opts)

    {:ok, _bound} =
      Staking.bind_submitted_hash(envelope.action_id, :approval, @approval_hash, opts)

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> DateTime.utc_now() end)

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    render_hook(view, "restore_staking_submission", %{})

    html = render(view)
    assert html =~ "this review stays open"
    assert html =~ "0xcdcdcd…cdcd"
    assert html =~ "may still confirm later"
    assert html =~ "before relying on the allowance state"
    refute html =~ "exact REGENT allowance remains onchain"
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

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-approval-revert", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
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
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-no-abandon", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    submit_action(view, action_id)

    render_hook(view, "abandon_staking_approval", %{})

    assert render(view) =~ "Staking transaction:"
    refute_push_event(view, "staking:abandoned", _)
  end

  test "unknown or mismatched confirmations fail closed", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-mismatch", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)

    render_hook(view, "confirm_staking", %{"action_id" => "other", "transaction_hash" => @tx_hash})

    assert render(view) =~ "does not match the reviewed action"
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
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-bounded", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
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
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-rejected", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)

    # A rejection the server cannot bind to a reviewed action is evidence of
    # nothing, so it never fabricates the neutral copy.
    render_hook(view, "staking_wallet_rejected", %{
      "action_id" => "other",
      "phase" => "action",
      "code" => 4001
    })

    refute render(view) =~ "Nothing was sent"

    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
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

    {:ok, account} =
      Accounts.register_verified("did:privy:stake-locked", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()

    submit_approval(view, prepared_action_id(render(view)))
    render_async(view)
    assert_push_event(view, "staking:prepared", %{})

    for action <- ~w(stake unstake claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(view, ~s(button[phx-value-action="#{action}"][disabled]))
    end

    # Verification stays available and never opens the wallet again.
    view |> element(~s(button[phx-click="retry_staking_approval_verification"])) |> render_click()
    render_async(view)
    refute_push_event(view, "staking:prepared", _)
  end

  test "U4_BASE_EXPLORER_TRUTH: each bound hash links to that exact transaction on Base", %{
    conn: conn
  } do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-explorer", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()
    action_id = prepared_action_id(render(view))

    submit_action(view, action_id)

    assert has_element?(
             view,
             ~s(.stake-submission a[href="https://basescan.org/tx/#{@approval_hash}"])
           )

    assert has_element?(view, ~s(.stake-submission a[href="https://basescan.org/tx/#{@tx_hash}"]))

    # An unbound hash is refused before it can be rendered at all, so no
    # malformed transaction link can exist.
    render_hook(view, "staking_submitted", %{
      "action_id" => action_id,
      "phase" => "action",
      "transaction_hash" => "0xnot-a-hash"
    })

    refute render(view) =~ "basescan.org/tx/0xnot-a-hash"
  end

  test "U5_EXPECTED_SIGNER_TRUTH: the review copies exactly the prepared signer", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:stake-signer", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    render_async(view)
    view |> form("#staking-amount-form", %{"amount" => "1"}) |> render_change()
    view |> element(~s(button[phx-value-action="stake"]), "Review stake") |> render_click()

    assert has_element?(view, ".stake-review .stake-mono", "0x1111…1111")

    assert has_element?(
             view,
             ~s(.stake-review button[data-copy-signer="#{@wallet}"][aria-label="Copy the full wallet address"])
           )
  end

  defp prepared_action_id(html) do
    [id] = Regex.run(~r/phx-value-action-id="([a-f0-9]+)"/, html, capture: :all_but_first)
    id
  end

  # The shell claims each dispatch before the wallet opens, so a submitted hash
  # only ever arrives for a phase the database already granted.
  defp sign(view, action_id),
    do: render_hook(view, "sign_prepared_staking", %{"action-id" => action_id})

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

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
