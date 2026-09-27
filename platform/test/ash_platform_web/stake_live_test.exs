defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.TestStakingChainClient
  alias AshPlatformWeb.StakeSteps

  # Invariants covered:
  # - smoke: 200 mount and the supply-bar landmark
  # - signed-out vs signed-in gating of send controls and refresh_data
  # - the server builds every wallet step and pushes them before any press
  # - allowance/approval branch, including a missing allowance
  # - a sent step is read on Base and its outcome is written by the server
  # - refresh_data is signed-in only; a rate-limited refusal keeps the last reading
  # - an unavailable figure renders as unavailable without hiding the page (gu2.18)
  # - a zero seven-day window is the 0.00 figure, not unavailable or never-asked (gu2.18)
  # - revenue-share and staked-share arithmetic, including truncation and unstake
  # - circulating supply arithmetic on the hero
  # - on-chain-button: an over-limit amount still reaches the wallet

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @second "0x3333333333333333333333333333333333333333"
  @hash "0x" <> String.duplicate("a", 64)
  @receipt_block 1_249
  @refresh_failure "Couldn’t update just now. The figures shown are from the last successful reading."
  @budget_refusal "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."
  @claim_controls ["Claim USDC", "Claim REGENT", "Claim and restake"]

  setup do
    SnapshotCache.clear()
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())

    Application.put_env(
      :ash_platform,
      :test_staking_denominator,
      "67000000000000000000000"
    )

    on_exit(fn ->
      for key <- [
            :test_staking_balances,
            :test_staking_circulating,
            :test_staking_denominator,
            :test_staking_protocol_error,
            :test_staking_wallet_error,
            :test_staking_paused,
            :test_staking_read_gate,
            :test_staking_read_at,
            :test_staking_usdc_7d,
            :test_staking_price_handler,
            :test_staking_transactions,
            :test_staking_receipts,
            :staking_snapshot_clock
          ] do
        Application.delete_env(:ash_platform, key)
      end

      SnapshotCache.clear()
    end)

    :ok
  end

  defmodule CrashingChainClient do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def protocol_snapshot, do: exit(:simulated_refresh_crash)

    @impl true
    def wallet_snapshot(_wallet), do: exit(:simulated_refresh_crash)

    @impl true
    def transaction(_hash), do: exit(:simulated_refresh_crash)

    @impl true
    def receipt(_hash), do: exit(:simulated_refresh_crash)
  end

  defmodule GatedChainClient do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def protocol_snapshot, do: AshPlatform.TestStakingChainClient.protocol_snapshot()

    @impl true
    def wallet_snapshot(wallet) do
      if test_pid = Application.get_env(:ash_platform, :test_staking_read_gate) do
        send(test_pid, {:staking_read_waiting, self()})

        receive do
          :continue_staking_read -> :ok
        after
          5_000 -> raise "timed out waiting to continue the staking read"
        end
      end

      AshPlatform.TestStakingChainClient.wallet_snapshot(wallet)
    end

    @impl true
    def transaction(hash), do: AshPlatform.TestStakingChainClient.transaction(hash)

    @impl true
    def receipt(hash), do: AshPlatform.TestStakingChainClient.receipt(hash)
  end

  test "PUBLIC_FACTS: anonymous visitors see benefits, contract facts, and a wallet connection",
       %{
         conn: conn
       } do
    view = mount_stake(conn)
    html = render(view)

    first_render = conn |> get("/stake") |> html_response(200)
    assert first_render =~ ~s(id="staking-supply-bar")
    refute first_render =~ "Loading staking contract data"
    assert has_element?(view, "#staking-supply-bar")
    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)

    for private_fact <- [
          "Available REGENT",
          "Currently staked",
          "Claimable USDC",
          "Claimable REGENT",
          @wallet
        ] do
      refute html =~ private_fact
    end

    refute has_element?(view, "#staking-amount")
    refute has_element?(view, "button[data-onchain-step]")
  end

  test "HERO_SUPPLY: the hero carries circulating and total REGENT", %{conn: conn} do
    view = mount_stake(conn)

    assert has_element?(view, ".stake-benefit-supply dt", "Circulating REGENT")
    assert has_element?(view, ".stake-benefit-supply dt", "Total REGENT")
    assert has_element?(view, ".stake-benefit-supply", "35 billion")
    assert has_element?(view, ".stake-benefit-supply", "100 billion")
    assert has_element?(view, ~s(.stake-benefit-supply [title="35,000,000,000.00"]))
    assert has_element?(view, ~s(.stake-benefit-supply [title="100,000,000,000"]))
  end

  test "MARKET_CAP: the supply figures carry the circulating market cap", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_price_handler, fn url ->
      {:ok,
       %{
         status: 200,
         body: AshPlatform.TestStakingPriceHttpClient.quote_body(url, "0.00000001", "2000")
       }}
    end)

    view = mount_stake(conn)
    assert has_element?(view, ".stake-benefit-supply", "Circulating MCAP")
    assert has_element?(view, ".stake-benefit-supply dd", "700k")
  end

  test "MARKET_CAP_UNAVAILABLE: a missing price is a dash rather than a figure", %{conn: conn} do
    view = mount_stake(conn)
    assert has_element?(view, ".stake-benefit-supply dd", "—")
  end

  test "NO_READ_FOR_A_VISITOR: an anonymous visit with no wallet reads Base not at all", %{
    conn: conn
  } do
    seed_snapshot()
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    {:ok, view, _html} = live(conn, "/stake")
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")

    refute_receive {:staking_read, _scope, _reader}, 200
  end

  test "ZERO_IS_A_FIGURE: a seven-day window with no deposits reads 0.00 USDC", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_usdc_7d, "0")

    view = mount_stake(conn)

    assert has_element?(view, ".stake-benefit-card-primary", "0.00 USDC")
    refute has_element?(view, ".figure-unavailable")
    refute render(view) =~ "yet"
  end

  test "UNAVAILABLE_WINDOW: a missing seven-day figure costs nothing else on the page", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_usdc_7d, :unavailable)

    view = stake_as_signer(conn, "unavailable-window")

    assert staking_assigns(view).staking_status == :ready
    refute render(view) =~ "Staking details are unavailable right now."

    assert has_element?(
             view,
             ".stake-benefit-card-primary .figure-unavailable",
             "Unavailable right now"
           )

    refute has_element?(view, ".stake-benefit-card-primary", "0.00 USDC")
    assert has_element?(view, ".stake-benefit-card-primary", "5,074.87 USDC")
    assert_every_claim_live(view)
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="stake"]:not([disabled])|)

    Application.delete_env(:ash_platform, :test_staking_usdc_7d)
    share_new_snapshot()
    render_async(view)
    assert has_element?(view, ".stake-benefit-card-primary", "1,250.50 USDC")
    refute has_element?(view, ".figure-unavailable")
  end

  test "CORE_READING_FAILS: the page keeps its layout without inventing contract facts", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)

    view = signed_in_stake(conn, "core-reading-fails")

    assert staking_assigns(view).staking_status == :error
    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    assert has_element?(view, ".stake-layout")
    assert has_element?(view, "#staking-contract-skeleton[aria-busy=false]")
    refute has_element?(view, "#staking-supply-bar")
    refute has_element?(view, "button[data-onchain-step]")

    assert has_element?(view, "button.stake-shared-refresh", "Read the contract")
    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    view |> element("button.stake-shared-refresh") |> render_click()
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
    refute render(view) =~ "Staking details are unavailable right now."
  end

  test "SUPPLY_SHARES: the bar and its label follow the three supply figures", %{conn: conn} do
    view = mount_stake(conn)

    assert has_element?(view, ~s(#staking-supply-bar [role="meter"][aria-valuenow="0"]))

    put_circulating("500000000000000000000")
    view = mount_stake(conn)

    assert has_element?(view, "#staking-supply-bar", "Circulating supply staked")
    assert has_element?(view, ~s(#staking-supply-bar [role="meter"][aria-valuenow="20"]))
  end

  test "SUPPLY_SHARE_TRUNCATES: a share landing halfway is cut rather than rounded up", %{
    conn: conn
  } do
    put_circulating("3200000000000000000000")

    view = mount_stake(conn)
    html = render(view)

    assert has_element?(view, "#staking-supply-bar", "3.12%")
    assert has_element?(view, ~s(#staking-supply-bar [role="meter"][aria-valuenow="3.12"]))
    refute html =~ "3.13"
  end

  test "UNAVAILABLE_SNAPSHOT: with no shared reading the page offers an anonymous visitor no control",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stake")
    html = render(view)

    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    refute has_element?(view, "button.stake-shared-refresh")
    refute html =~ @wallet
  end

  test "UNAVAILABLE_SNAPSHOT_SIGNED_IN: a signed-in visitor is offered the shared reading", %{
    conn: conn
  } do
    view = signed_in_stake(conn, "unavailable-shared")

    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    assert has_element?(view, "button.stake-shared-refresh", "Read the contract")

    view |> element("button.stake-shared-refresh") |> render_click()
    assert render_async(view) =~ "Base block #1,234"
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
  end

  test "SHARED_REFRESH_IS_SIGNED_IN_ONLY: an anonymous socket is refused server-side", %{
    conn: conn
  } do
    view = mount_stake(conn)
    refute has_element?(view, "button.stake-shared-refresh")

    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    Application.put_env(:ash_platform, :staking_snapshot_clock, fn -> 10_000_000 end)

    render_hook(view, "refresh_shared_snapshot", %{})
    render_hook(view, "refresh_data", %{})

    refute_receive {:staking_read, _scope, _reader}, 200
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
  end

  test "SHARED_REFRESH_BUDGET: a refusal says so in its own words, not as a Base failure", %{
    conn: conn
  } do
    seed_snapshot()
    view = conn |> signed_in_stake("shared-budget") |> activate(@wallet)
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    html = render_async(view)

    assert html =~ @budget_refusal
    refute html =~ @refresh_failure
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
  end

  test "REFRESH_DATA: one click reads this wallet's position and the contract everyone shares", %{
    conn: conn
  } do
    seed_snapshot()
    view = conn |> signed_in_stake("refresh-data") |> activate(@wallet)

    assert has_element?(view, ".stake-wallet-block", "Base block #1,240")
    assert has_element?(view, ".stake-snapshot-note", "Base block #1,234")

    Application.put_env(:ash_platform, :test_staking_wallet_block, @receipt_block)
    Application.put_env(:ash_platform, :test_staking_protocol_block, 9_876)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_staking_wallet_block)
      Application.delete_env(:ash_platform, :test_staking_protocol_block)
    end)

    Application.put_env(:ash_platform, :staking_snapshot_clock, fn -> 10_000_000 end)

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    assert_receive {:staking_snapshot, _snapshot}
    render_async(view)

    assert has_element?(view, ".stake-wallet-block", "Base block #1,249")
    assert has_element?(view, ".stake-snapshot-note", "Base block #9,876")
  end

  test "SHARED_FAN_OUT: one visitor's reading reaches another page without touching its wallet",
       %{
         conn: conn
       } do
    view = conn |> mount_stake() |> activate(@wallet)
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    Application.put_env(:ash_platform, :test_staking_protocol_block, 9_876)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_protocol_block) end)

    share_new_snapshot()
    assert render_async(view) =~ "Base block #9,876"

    assert has_element?(view, ".stake-wallet-block", "Base block #1,240")
    assert render(view) =~ "5 REGENT"
  end

  test "CONFIRMED_STEP_REFRESHES: a step Base confirmed re-reads the wallet and the shared totals",
       %{conn: conn} do
    view = stake_as_signer(conn, "confirmed-refresh")
    on_exit(fn -> SnapshotCache.clear() end)
    set_amount(view, "1")

    assert staking_assigns(view).staking.wallet_block_number ==
             TestStakingChainClient.wallet_block()

    assert :sys.get_state(SnapshotCache).refresh_timer == nil

    reverted = hash("0b")
    send_landed(view, "stake", reverted, "0x0")
    assert has_element?(view, ~s(#staking-sent-#{reverted}[data-outcome="reverted"]))
    assert :sys.get_state(SnapshotCache).refresh_timer == nil

    Application.put_env(:ash_platform, :test_staking_wallet_block, @receipt_block)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_wallet_block) end)

    send_landed(view, "stake", @hash, "0x1")

    assert has_element?(view, ~s(#staking-sent-#{@hash}[data-outcome="confirmed"]))
    assert staking_assigns(view).staking.wallet_block_number == @receipt_block
    assert {timer, _token} = :sys.get_state(SnapshotCache).refresh_timer
    assert Process.read_timer(timer) <= 10_000
  end

  test "ANONYMOUS_ACTIVE_WALLET: any connected wallet is read without a Regent login", %{
    conn: conn
  } do
    view = mount_stake(conn)
    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)
    refute has_element?(view, "#staking-amount")

    activate(view, @other)
    assert has_element?(view, "#staking-amount")

    activate(view, @wallet)
    assert has_element?(view, "#staking-amount")
    assert has_element?(view, ".stake-wallet-summary")
    assert render(view) =~ "5 REGENT"
    assert has_element?(view, ~s(#account-control button[data-account-target="sign-in"]))
  end

  test "SIGN_IN_BEFORE_SENDING: a wallet with no sign-in reads its position and sends nothing", %{
    conn: conn
  } do
    view = conn |> mount_stake() |> activate(@wallet)

    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    assert_offers_sign_in(view)
  end

  test "WALLET_MISMATCH: a wallet that is not the account's sends nothing and the figures stay",
       %{conn: conn} do
    view = stake_as_signer(conn, "wallet-mismatch")
    refute has_element?(view, ".shell-sending-wallet")

    activate(view, @other)

    assert staking_assigns(view).staking_wallet == @wallet
    assert staking_assigns(view).staking_review.signer == @wallet
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="stake"]|)
    assert has_element?(view, ".shell-sending-wallet", "0x2222…2222")
    assert has_element?(view, ".shell-sending-wallet", "0x1111…1111")

    activate(view, @wallet)
    refute has_element?(view, ".shell-sending-wallet")
  end

  test "LINKED_WALLET: the active wallet acts whenever it is one of the account's own", %{
    conn: conn
  } do
    seed_snapshot()

    assert {:ok, account} =
             Accounts.register_verified("did:privy:linked-wallet", @wallet, [@wallet, @second],
               actor: %System{}
             )

    {:ok, view, _html} =
      conn |> init_test_session(%{human_account_id: account.id}) |> live("/stake")

    activate(view, @second)
    assert staking_assigns(view).staking_wallet == @second
    assert staking_assigns(view).staking_review.signer == @second
    assert has_element?(view, ".stake-signer[title='#{@second}']")
    refute has_element?(view, ".shell-sending-wallet")

    send_landed(view, "claim_usdc", @hash, "0x1")
    assert has_element?(view, "#staking-sent-#{@hash}", "Done. Your USDC rewards were claimed.")

    # A wallet that is not the account's is one to switch away from.
    activate(view, @other)
    assert staking_assigns(view).staking_wallet == @wallet
    assert has_element?(view, ".shell-sending-wallet", "isn't linked to your account")
  end

  test "APPROVAL_PER_WALLET: an approval counts for the wallet that sent it, even after a switch",
       %{conn: conn} do
    seed_snapshot()

    assert {:ok, account} =
             Accounts.register_verified("did:privy:approval-wallet", @wallet, [@wallet, @second],
               actor: %System{}
             )

    {:ok, view, _html} =
      conn |> init_test_session(%{human_account_id: account.id}) |> live("/stake")

    view = activate(view, @wallet)
    set_amount(view, "1")
    approval = approval_from(view, @wallet)

    # The press was still in the wallet when the person switched wallets. The
    # approval's calldata is the same for both, and Base's sender picks the step.
    activate(view, @second)
    put_chain(:test_staking_transactions, @hash, approval)
    put_chain(:test_staking_receipts, @hash, %{"status" => "0x1"})

    render_hook(view, "step_sent", %{
      "step" => "approve",
      "transaction_hash" => @hash,
      "data" => approval["input"],
      "from" => @wallet
    })

    render_async(view)
    assert has_element?(view, "#staking-sent-#{@hash}", "Approved. You can stake now.")

    # An approval on its way skips the approve step only for the wallet that sent
    # it, and only while Base is still being asked about it.
    set_amount(view, "1")
    assigns = staking_assigns(view)
    [sent] = assigns.staking_sent
    on_its_way = %{sent | outcome: :pending, reads: 1}
    assert StakeSteps.next_step(%{assigns | staking_sent: [on_its_way]}) == "approve"

    for_second = %{on_its_way | built: %{sent.built | signer: @second}}
    assert StakeSteps.next_step(%{assigns | staking_sent: [for_second]}) == "stake"

    assert StakeSteps.next_step(%{assigns | staking_sent: [%{for_second | reads: 90}]}) ==
             "approve"
  end

  test "ACCOUNT_POSITION: a signed-in page opens on the account's wallet before the browser reports one",
       %{conn: conn} do
    seed_snapshot()
    view = signed_in_stake(conn, "account-position")

    assert staking_assigns(view).staking_wallet == @wallet
    refute has_element?(view, ".stake-connect-flow")
    refute has_element?(view, ".shell-sending-wallet")
  end

  test "DISCONNECTED_WALLET: releasing every wallet clears the position and offers the connection again",
       %{conn: conn} do
    view = conn |> mount_stake() |> activate(@wallet)

    assert staking_assigns(view).staking_wallet == @wallet
    assert has_element?(view, "#staking-amount")

    activate(view, nil)

    assigns = staking_assigns(view)
    assert assigns.staking_wallet == nil
    assert assigns.staking_amount == ""

    for key <- AshPlatform.Staking.Facts.wallet_keys() do
      assert Map.fetch!(assigns.staking, key) == nil
    end

    assert has_element?(view, ~s|button[data-account-target="sign-in"]|)
    refute has_element?(view, "#staking-amount")
    refute render(view) =~ "Currently staked"
  end

  test "SERVER_BUILT_STEPS: the page is handed every wallet step before anyone presses", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "server-built")
    set_amount(view, "1")

    assert_push_event(view, "onchain-steps:review", %{
      component_id: "regent-staking",
      signer: @wallet,
      chain: %{chain_id: 8453},
      inputs: %{action: "stake", amount: "1"},
      steps: [
        %{step: "approve", data: "0x095ea7b3" <> _},
        %{step: "stake", data: "0x7acb7757" <> _},
        %{step: "claim_usdc"},
        %{step: "claim_regent"},
        %{step: "claim_and_restake_regent"}
      ]
    })

    assert has_element?(view, ~s|#staking-primary[data-onchain-step="approve"]|, "Approve REGENT")
    assert has_element?(view, ".stake-approval-note", "needs an exact REGENT approval first")

    # An approval on its way moves the button on to the stake itself, and one
    # Base turned down brings the approval back.
    send_step(view, "approve", @hash)
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="stake"]|, "Stake REGENT")
    assert has_element?(view, ".stake-approval-note", "Approval sent.")

    # Asked again straight away, Base's answer comes back without the wait.
    land(view, "approve", @hash, "0x0")
    render_hook(view, "check_staking_step", %{"hash" => @hash})
    render_async(view)
    assert has_element?(view, ~s(#staking-sent-#{@hash}[data-outcome="reverted"]))
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="approve"]|)

    # A landed approval leaves it to the wallet reading taken after it. This one
    # still shows no allowance, as it does once a stake has spent the approval.
    send_landed(view, "approve", hash("0a"), "0x1")
    assert has_element?(view, ~s(#staking-sent-#{hash("0a")}[data-outcome="confirmed"]))
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="approve"]|)

    view |> element(~s(button[phx-value-mode="unstake"])) |> render_click()
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="unstake"]|, "Unstake REGENT")
    refute has_element?(view, ".stake-approval-note")
  end

  test "AMOUNT_LIMITS: Max follows capacity and an over-limit amount still reaches the wallet", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "105000000000000000000")
    view = stake_as_signer(conn, "amount-limits")

    view |> element(~s(button[phx-value-portion="max"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="5"]))

    set_amount(view, "11")
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="approve"]:not([disabled])|)

    assert %{steps: [%{step: "approve"}, %{step: "stake"} | _claims]} =
             staking_assigns(view).staking_review
  end

  test "REVENUE_SHARE: the preview reads a staker's share of revenue against the whole supply", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_balances, %{
      @wallet => %{
        stake: "1500000000000000000000000000",
        token: "1000000000000000000000000000"
      }
    })

    Application.put_env(
      :ash_platform,
      :test_staking_denominator,
      "9" <> String.duplicate("0", 30)
    )

    view = stake_as_signer(conn, "revenue-share")

    set_amount(view, "500000000")
    html = render(view)

    assert html =~ "USDC Revenue Share"
    refute html =~ "Pool share"
    assert html =~ "2.0000%"

    set_amount(view, "89999999")
    assert render(view) =~ "1.5899%"

    view |> element(~s(button[phx-value-mode="unstake"])) |> render_click()
    set_amount(view, "500000000")
    assert render(view) =~ "1.0000%"
  end

  test "REFRESH_FAILURE: failed and crashed refreshes preserve the last snapshot", %{conn: conn} do
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)
    on_exit(fn -> Application.put_env(:ash_platform, :staking_chain_client, previous_client) end)

    view = conn |> mount_stake() |> activate(@wallet)
    Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)
    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Live contract position")
    assert render(view) =~ @refresh_failure

    Application.delete_env(:ash_platform, :test_staking_wallet_error)
    Application.put_env(:ash_platform, :staking_chain_client, CrashingChainClient)
    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Live contract position")
    assert render(view) =~ @refresh_failure

    Application.put_env(:ash_platform, :staking_chain_client, previous_client)
    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Live contract position")
    refute render(view) =~ @refresh_failure
  end

  test "FIRST_WALLET_READ_FAILURE: only this wallet's figures go missing", %{conn: conn} do
    view = stake_as_signer(conn, "first-wallet-failure")
    Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")

    assert has_element?(
             view,
             ".stake-wallet-summary .figure-unavailable",
             "Unavailable right now"
           )

    refute render(view) =~ "Staking details are unavailable right now."
    assert_every_claim_live(view)
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="stake"]:not([disabled])|)

    set_amount(view, "3")
    assert has_element?(view, ~s|#staking-primary[data-onchain-step="approve"]:not([disabled])|)
    assert has_element?(view, ".stake-approval-note", "needs an exact REGENT approval first")
  end

  test "WALLET_DURING_FIRST_READ: replacing the open wallet read never reports Base unavailable",
       %{conn: conn} do
    swap_client(GatedChainClient)
    Application.put_env(:ash_platform, :test_staking_read_gate, self())

    view = mount_stake(conn)
    render_hook(view, "staking_active_wallet", %{"address" => @other})
    assert_receive {:staking_read_waiting, first_read}
    first_read_ref = Process.monitor(first_read)

    render_hook(view, "staking_active_wallet", %{"address" => @wallet})

    assert_receive {:staking_read_waiting, second_read}
    assert_receive {:DOWN, ^first_read_ref, :process, ^first_read, _reason}

    refute render(view) =~ "Staking details are unavailable right now."
    refute render(view) =~ @refresh_failure
    assert staking_assigns(view).staking_status == :ready

    Application.delete_env(:ash_platform, :test_staking_read_gate)
    send(second_read, :continue_staking_read)
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
  end

  test "COLD_START_WALLET: connecting a wallet with no contract reading buys no chain read", %{
    conn: conn
  } do
    first_render = conn |> get("/stake") |> html_response(200)
    assert first_render =~ ~s(id="staking-benefits-skeleton")
    assert first_render =~ ~s(id="staking-contract-skeleton")
    assert first_render =~ ~s(id="staking-revenue-sources")
    refute first_render =~ "Loading staking contract data"
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    {:ok, view, _html} = live(conn, "/stake")
    render_hook(view, "staking_active_wallet", %{"address" => @wallet})

    refute_receive {:staking_read, _scope, _reader}, 200
    assert staking_assigns(view).staking_status == :error
    refute has_element?(view, ".stake-wallet-summary")

    share_new_snapshot()
    render_async(view)

    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
  end

  test "STEP_OUTCOMES: the server reads each sent step on Base and says what happened", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "step-outcomes")

    for {name, hash, status, words} <- [
          {"claim_usdc", hash("01"), "0x1", "Done. Your USDC rewards were claimed."},
          {"claim_regent", hash("02"), "0x0", "There may be no REGENT rewards to claim yet"},
          {"claim_and_restake_regent", hash("03"), "0x1", "added to your stake"}
        ] do
      send_landed(view, name, hash, status)
      assert has_element?(view, "#staking-sent-#{hash}", words)
    end

    # Nothing on Base yet is still waiting, and Base is asked again.
    waiting = hash("04")
    send_step(view, "claim_usdc", waiting)

    assert has_element?(
             view,
             ~s(#staking-sent-#{waiting}[data-outcome="pending"]),
             "Waiting for Base"
           )

    land(view, "claim_usdc", waiting, "0x1")
    render_async(view, 3_000)
    assert has_element?(view, ~s(#staking-sent-#{waiting}[data-outcome="confirmed"]))
  end

  test "EVERY_PRESS_IS_FOLLOWED: repeated presses each get their own line", %{conn: conn} do
    view = stake_as_signer(conn, "every-press")

    for byte <- ~w(11 12 13), do: send_step(view, "claim_usdc", hash(byte))

    for byte <- ~w(11 12 13) do
      assert has_element?(view, "#staking-sent-#{hash(byte)}", "USDC claim")
    end
  end

  test "NOT_THIS_STEP: a hash that is not the step this page built is not followed", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "not-this-step")
    [%{data: data}] = step(view, "claim_usdc")

    Application.put_env(:ash_platform, :test_staking_transactions, %{
      @hash => %{"from" => @other, "to" => staking_contract(), "input" => data, "value" => "0x0"}
    })

    send_step(view, "claim_usdc", @hash)
    render_async(view)
    assert has_element?(view, "#staking-sent-#{@hash}", "not the one this page prepared")

    # Calldata the page never built is not read on Base at all.
    unknown = hash("21")

    render_hook(view, "step_sent", %{
      "step" => "stake",
      "transaction_hash" => unknown,
      "data" => "0x7acb7757",
      "from" => @wallet
    })

    assert has_element?(view, "#staking-sent-#{unknown}", "not the one this page prepared")

    render_hook(view, "step_sent", %{
      "step" => "stake",
      "transaction_hash" => "0x12",
      "data" => "0x",
      "from" => @wallet
    })

    refute has_element?(view, "#staking-sent-0x12")
  end

  test "PRESS_FAILURES: a press the wallet did not send says why in plain words", %{conn: conn} do
    view = stake_as_signer(conn, "press-failures")

    for {reason, words} <- [
          {"wallet_declined", "Your wallet declined this. Nothing was sent."},
          {"network_mismatch", "Switch it to Base"},
          {"wallet_unavailable", "Select a wallet on your account in your wallet app"},
          {"insufficient_funds", "not have enough ETH on Base to pay the network fee"},
          {"send_unconfirmed", "Your wallet may have sent this."},
          {"step_unknown", "Enter an amount in REGENT above zero."}
        ] do
      render_hook(view, "step_failed", %{"step" => "stake", "reason" => reason})
      assert has_element?(view, "#staking-press-notice", words)
    end

    set_amount(view, "1")
    stake_for(view, "0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe")
    render_hook(view, "step_failed", %{"step" => "stake", "reason" => "step_unknown"})

    assert has_element?(
             view,
             "#staking-press-notice",
             "Tick the warning about the receiving address"
           )

    send_landed(view, "claim_usdc", @hash, "0x1")
    refute has_element?(view, "#staking-press-notice")
  end

  test "TURNED_DOWN: a stake Base refused says when staking is paused or full", %{conn: conn} do
    view = stake_as_signer(conn, "turned-down")
    set_amount(view, "1")
    send_landed(view, "stake", hash("31"), "0x0")
    assert has_element?(view, "#staking-sent-#{hash("31")}", "the approval had not landed yet")

    Application.put_env(:ash_platform, :test_staking_paused, true)
    share_new_snapshot()
    render_async(view)

    for {name, byte} <- [{"stake", "32"}, {"claim_and_restake_regent", "33"}] do
      send_landed(view, name, hash(byte), "0x0")
      assert has_element?(view, "#staking-sent-#{hash(byte)}", "Staking is paused on Base")
    end

    # A stake Base refused before the pause keeps the reason it had then.
    assert has_element?(view, "#staking-sent-#{hash("31")}", "the approval had not landed yet")

    Application.put_env(:ash_platform, :test_staking_paused, false)
    Application.put_env(:ash_platform, :test_staking_denominator, "0")
    share_new_snapshot()
    render_async(view)

    send_landed(view, "stake", hash("35"), "0x0")
    assert has_element?(view, "#staking-sent-#{hash("35")}", "cannot take that much more REGENT")
    assert has_element?(view, "#staking-sent-#{hash("32")}", "Staking is paused on Base")

    # A claim that pays out is never refused for either reason.
    send_landed(view, "claim_usdc", hash("34"), "0x0")
    assert has_element?(view, "#staking-sent-#{hash("34")}", "There may be no USDC to claim yet")
  end

  test "STAKE_FOR_SOMEONE: the step to another wallet exists only for the address acknowledged",
       %{conn: conn} do
    other = "0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe"
    view = stake_as_signer(conn, "stake-for")
    set_amount(view, "1")

    stake_for(view, "not an address")
    assert has_element?(view, "#staking-recipient-error:not([hidden])")
    refute has_element?(view, "#staking-recipient-warning")

    stake_for(view, other)
    assert has_element?(view, "#staking-recipient-warning-text", String.downcase(other))
    assert step(view, "stake") == []

    acknowledge(view, other)
    assert [%{data: data}] = step(view, "stake")
    assert data =~ "de0b295669a9fd93d5f28d9ec85e40f4cb697bae"

    # Another address takes the acknowledgment back.
    stake_for(view, @other)
    assert step(view, "stake") == []
    refute has_element?(view, "#staking-recipient-acknowledged[checked]")
  end

  test "PREPARE_AND_SEND: a press ahead of the form gets the matching step to send", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "prepare-and-send")

    form = %{
      "action" => "stake",
      "amount" => "7",
      "for_other" => false,
      "receiver" => "",
      "acknowledged" => false
    }

    render_hook(view, "prepare_and_send", %{"form" => form})

    assert_reply(view, %{
      send: "approve",
      review: %{
        signer: @wallet,
        inputs: %{amount: "7"},
        steps: [%{step: "approve"}, %{step: "stake"} | _claims]
      }
    })

    assert has_element?(view, ~s(#staking-amount[value="7"]))
  end

  defp hash(byte), do: "0x" <> String.duplicate(byte, 32)

  defp staking_contract, do: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"

  defp step(view, name),
    do: Enum.filter(staking_assigns(view).staking_review.steps, &(&1.step == name))

  # Base answers for `hash` as though it carried the page's own `name` step.
  defp land(view, name, hash, status) do
    [%{to: to, data: data, value: value}] = step(view, name)
    signer = staking_assigns(view).staking_review.signer
    transaction = %{"from" => signer, "to" => to, "input" => data, "value" => value}
    put_chain(:test_staking_transactions, hash, transaction)
    put_chain(:test_staking_receipts, hash, %{"status" => status})
  end

  # The page's approval step as Base shows it when `from` sent it.
  defp approval_from(view, from) do
    [%{to: to, data: data, value: value}] = step(view, "approve")
    %{"from" => from, "to" => to, "input" => data, "value" => value}
  end

  defp put_chain(key, hash, value) do
    entries = Application.get_env(:ash_platform, key, %{})
    Application.put_env(:ash_platform, key, Map.put(entries, hash, value))
  end

  # What the browser reports after the wallet sent `name` from the page's review.
  # Base is read at once; a step it does not know yet is read again later.
  defp send_step(view, name, hash) do
    [%{data: data}] = step(view, name)
    from = staking_assigns(view).staking_review.signer

    render_hook(view, "step_sent", %{
      "step" => name,
      "transaction_hash" => hash,
      "data" => data,
      "from" => from
    })
  end

  # A step Base already answered for, sent and read.
  defp send_landed(view, name, hash, status) do
    land(view, name, hash, status)
    send_step(view, name, hash)
    render_async(view)
  end

  defp stake_for(view, receiver) do
    view
    |> form("#staking-amount-form", %{"for_other" => "true", "receiver" => receiver})
    |> render_change(%{"_target" => ["receiver"]})
  end

  defp acknowledge(view, receiver) do
    view
    |> form("#staking-amount-form", %{
      "for_other" => "true",
      "receiver" => receiver,
      "acknowledged" => "true"
    })
    |> render_change(%{"_target" => ["acknowledged"]})
  end

  defp assert_every_claim_live(view) do
    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(
               view,
               ~s|button[data-claim="#{action}"][data-onchain-step="#{action}"]:not([disabled])|
             )
    end

    refute has_element?(view, "button[data-onchain-step][disabled]")
  end

  defp set_amount(view, amount),
    do: view |> form("#staking-amount-form", %{"amount" => amount}) |> render_change()

  defp seed_snapshot do
    SnapshotCache.clear()
    assert :ok = SnapshotCache.refresh(self())
    assert_receive {:staking_snapshot, snapshot}
    snapshot
  end

  defp share_new_snapshot do
    SnapshotCache.clear()
    assert :ok = SnapshotCache.refresh(self())
    assert_receive {:staking_snapshot, _snapshot}
    :ok
  end

  defp mount_stake(conn) do
    seed_snapshot()
    {:ok, view, _html} = live(conn, "/stake")

    view
  end

  defp stake_as_signer(conn, suffix) do
    seed_snapshot()
    conn |> signed_in_stake(suffix) |> activate(@wallet)
  end

  defp assert_offers_sign_in(view) do
    refute has_element?(view, "button[data-onchain-step]")

    for label <- ["Stake REGENT" | @claim_controls] do
      assert has_element?(view, sign_in_control(), label)
    end

    view |> element(~s|.stake-mode button[phx-value-mode="unstake"]|) |> render_click()
    assert has_element?(view, sign_in_control(), "Unstake REGENT")
    view |> element(~s|.stake-mode button[phx-value-mode="stake"]|) |> render_click()
  end

  defp sign_in_control,
    do: ~s|#regent-staking button[data-account-target="sign-in"]:not([data-onchain-step])|

  defp signed_in_stake(conn, suffix) do
    assert {:ok, account} =
             Accounts.register_verified("did:privy:#{suffix}", @wallet, [@wallet],
               actor: %System{}
             )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    view
  end

  defp swap_client(module) do
    previous = Application.get_env(:ash_platform, :staking_chain_client)
    Application.put_env(:ash_platform, :staking_chain_client, module)
    on_exit(fn -> Application.put_env(:ash_platform, :staking_chain_client, previous) end)
  end

  defp put_circulating(atomic) do
    Application.put_env(:ash_platform, :test_staking_circulating, atomic)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_circulating) end)
  end

  defp staking_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp activate(view, wallet) do
    render_hook(view, "staking_active_wallet", %{"address" => wallet})
    render_async(view)
    view
  end
end
