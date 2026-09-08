defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.TestStakingChainClient

  # Invariants covered:
  # - smoke: 200 mount and the supply-bar landmark
  # - signed-out vs signed-in gating of send controls and refresh_data
  # - wallet handoff via browser data attributes (no prepare_staking event)
  # - allowance/approval branch, including a missing allowance
  # - refresh_data is signed-in only; a rate-limited refusal keeps the last reading
  # - an unavailable figure renders as unavailable without hiding the page (gu2.18)
  # - a zero seven-day window is the 0.00 figure, not unavailable or never-asked (gu2.18)
  # - revenue-share and staked-share arithmetic, including truncation and unstake
  # - circulating supply arithmetic on the hero
  # - on-chain-button: an over-limit amount still reaches the wallet

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @hash "0x" <> String.duplicate("a", 64)
  @receipt_block 1_249
  @refresh_failure "Refresh failed. The last confirmed Base snapshot remains on screen."
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
            :test_staking_allowance,
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
            :test_wallet_observation_watcher,
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
    def allowance(_wallet, _amount), do: {:ok, :insufficient}
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
    def allowance(wallet, amount),
      do: AshPlatform.TestStakingChainClient.allowance(wallet, amount)
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
    refute has_element?(view, "button[data-staking-action]")
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
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

  test "MARKET_CAP: the token links carry the circulating market cap", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_price_handler, fn url ->
      {:ok,
       %{
         status: 200,
         body: AshPlatform.TestStakingPriceHttpClient.quote_body(url, "0.00000001", "2000")
       }}
    end)

    view = mount_stake(conn)
    assert has_element?(view, ".stake-market-cap", "700k market cap")
  end

  test "MARKET_CAP_UNAVAILABLE: a missing price is a dash rather than a figure", %{conn: conn} do
    view = mount_stake(conn)
    assert has_element?(view, ".stake-market-cap", "— market cap")
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
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)

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
    refute has_element?(view, "button[data-staking-action]")

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

  test "POST_CONFIRMATION_REFRESH: the wallet is re-read at the receipt's block, not the cached one",
       %{conn: conn} do
    view = conn |> mount_stake() |> activate(@wallet)

    assert staking_assigns(view).staking.wallet_block_number ==
             TestStakingChainClient.wallet_block()

    Application.put_env(:ash_platform, :test_staking_wallet_block, @receipt_block)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_wallet_block) end)

    render_hook(view, "refresh_staking", %{})
    render_async(view)

    staking = staking_assigns(view).staking
    assert staking.wallet_block_number == @receipt_block
    assert staking.wallet_block_number > TestStakingChainClient.wallet_block()
    assert staking.block_number == TestStakingChainClient.protocol_block()
    assert SnapshotCache.snapshot().block_number == TestStakingChainClient.protocol_block()
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

  test "WALLET_MISMATCH: a sign-in on one wallet cannot send from another", %{conn: conn} do
    view = stake_as_signer(conn, "wallet-mismatch")

    assert has_element?(view, ~s(#regent-staking[data-staking-signer="#{@wallet}"]))
    assert has_element?(view, ~s|button[data-staking-action="stake"]|)

    activate(view, @other)
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    assert_refuses_every_action(
      view,
      "You must disconnect 0x1111…1111 and connect again with wallet address 0x2222…2222."
    )

    activate(view, @wallet)
    assert has_element?(view, ~s(#regent-staking[data-staking-signer="#{@wallet}"]))
    assert has_element?(view, ~s|button[data-staking-action="stake"]|)
    refute render(view) =~ "You must disconnect"
  end

  test "REFUSAL_IS_ONLY_A_REFUSAL: the event changes nothing when there is nothing to refuse", %{
    conn: conn
  } do
    for view <- [conn |> mount_stake() |> activate(@wallet), stake_as_signer(conn, "no-refusal")] do
      Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)
      view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
      render_async(view)
      Application.delete_env(:ash_platform, :test_staking_wallet_error)
      assert render(view) =~ @refresh_failure

      render_hook(view, "refuse_staking_action", %{})

      assert render(view) =~ @refresh_failure
      refute render(view) =~ "You must disconnect"
    end
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
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    refute render(view) =~ "Currently staked"
  end

  test "DIRECT_STAKE: canonical browser data renders without a server preparation event", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "direct-stake")
    set_amount(view, "1")

    assert has_element?(
             view,
             ~s(#regent-staking[data-staking-chain-id="8453"][data-staking-signer="#{@wallet}"][data-staking-allowance="0"])
           )

    assert has_element?(view, ~s(button[data-staking-action="stake"]))
    refute has_element?(view, "[phx-click=prepare_staking]")
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "AMOUNT_LIMITS: Max follows capacity and an over-limit amount still reaches the wallet", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "105000000000000000000")
    view = stake_as_signer(conn, "amount-limits")

    view |> element(~s(button[phx-value-portion="max"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="5"]))

    set_amount(view, "11")
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
    refute_push_event(view, "staking:wallet-action", _)
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
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)

    set_amount(view, "3")
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    assert render(view) =~ "will first request an exact REGENT approval"
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

  test "OBSERVATION_REPORTS: a well-formed observation returns the Base outcome to the page", %{
    conn: conn
  } do
    view = watched_stake(conn)

    render_hook(view, "observe_staking_transaction", observation("obs-1"))

    assert_receive {:wallet_observation, :staking, transaction, observer}
    assert transaction["hash"] == @hash
    assert transaction["signer"] == @wallet
    refute Map.has_key?(transaction, "observation_id")

    send(observer, {:wallet_observation_result, :success})
    render_async(view)

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :success
    })
  end

  test "OBSERVATION_IS_NOT_REPEATED: a duplicate observation id observes Base once", %{conn: conn} do
    view = watched_stake(conn)

    render_hook(view, "observe_staking_transaction", observation("obs-1"))
    assert_receive {:wallet_observation, :staking, _transaction, observer}

    render_hook(view, "observe_staking_transaction", observation("obs-1"))
    refute_receive {:wallet_observation, _scope, _transaction, _observer}, 200

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :unavailable
    })

    send(observer, {:wallet_observation_result, :success})
    render_async(view)
  end

  test "OBSERVATION_IS_CAPPED: a ninth live observation on one socket observes nothing", %{
    conn: conn
  } do
    view = watched_stake(conn)

    observers =
      for index <- 1..8 do
        render_hook(view, "observe_staking_transaction", observation("obs-#{index}"))
        assert_receive {:wallet_observation, :staking, _transaction, observer}
        observer
      end

    render_hook(view, "observe_staking_transaction", observation("obs-9"))
    refute_receive {:wallet_observation, _scope, _transaction, _observer}, 200

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-9",
      result: :unavailable
    })

    [first | held] = observers
    send(first, {:wallet_observation_result, :success})

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :success
    })

    render_hook(view, "observe_staking_transaction", observation("obs-9"))
    assert_receive {:wallet_observation, :staking, _transaction, ninth}

    for observer <- [ninth | held], do: send(observer, {:wallet_observation_result, :success})
    render_async(view)
  end

  test "OBSERVATION_SURVIVES_A_CRASH: a crashed observer releases its place and reports", %{
    conn: conn
  } do
    view = watched_stake(conn)

    render_hook(view, "observe_staking_transaction", observation("obs-1"))
    assert_receive {:wallet_observation, :staking, _transaction, observer}

    send(observer, {:wallet_observation_result, :crash})

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :unavailable
    })

    render_hook(view, "observe_staking_transaction", observation("obs-1"))
    assert_receive {:wallet_observation, :staking, _transaction, retried}

    send(retried, {:wallet_observation_result, :success})
    render_async(view)

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :success
    })
  end

  test "OBSERVATION_NEEDS_AN_ID: a malformed observation observes nothing", %{conn: conn} do
    view = watched_stake(conn)

    render_hook(
      view,
      "observe_staking_transaction",
      Map.delete(observation("obs-1"), "observation_id")
    )

    render_hook(view, "observe_staking_transaction", %{"hash" => @hash})
    render_hook(view, "observe_staking_transaction", %{"observation_id" => ""})
    render_hook(view, "observe_staking_transaction", %{"observation_id" => 7})

    render_hook(view, "observe_staking_transaction", %{
      "observation_id" => String.duplicate("i", 129)
    })

    refute_receive {:wallet_observation, _scope, _transaction, _observer}, 200
  end

  defp watched_stake(conn) do
    view = mount_stake(conn)
    Application.put_env(:ash_platform, :test_wallet_observation_watcher, self())
    view
  end

  defp observation(id),
    do: %{
      "observation_id" => id,
      "hash" => @hash,
      "signer" => @wallet,
      "to" => "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
      "data" => "0xa9059cbb"
    }

  defp assert_every_claim_live(view) do
    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(view, ~s|button[data-staking-action="#{action}"]:not([disabled])|)
    end

    refute has_element?(view, "button[data-staking-action][disabled]")
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
    refute has_element?(view, "#regent-staking[data-staking-signer]")
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    refute has_element?(view, "button[data-staking-action]")

    for label <- ["Stake REGENT" | @claim_controls] do
      assert has_element?(view, sign_in_control(), label)
    end

    view |> element(~s|.stake-mode button[phx-value-mode="unstake"]|) |> render_click()
    assert has_element?(view, sign_in_control(), "Unstake REGENT")
    view |> element(~s|.stake-mode button[phx-value-mode="stake"]|) |> render_click()
  end

  defp sign_in_control,
    do: ~s|#regent-staking button[data-account-target="sign-in"]:not([data-staking-action])|

  defp assert_refuses_every_action(view, refusal) do
    refute has_element?(view, "#regent-staking[data-staking-signer]")
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    refute has_element?(view, "button[data-staking-action]")

    for label <- ["Stake REGENT" | @claim_controls] do
      view |> element("#regent-staking button", label) |> render_click()
      assert render(view) =~ refusal
    end

    view |> element(~s|.stake-mode button[phx-value-mode="unstake"]|) |> render_click()
    view |> element("#regent-staking button", "Unstake REGENT") |> render_click()
    assert render(view) =~ refusal

    view |> element(~s|.stake-mode button[phx-value-mode="stake"]|) |> render_click()
  end

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
