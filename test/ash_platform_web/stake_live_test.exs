defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.TestStakingChainClient
  alias AshPlatformWeb.ShellLive

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @contract "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @regent "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  @usdc "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
  @hash "0x" <> String.duplicate("a", 64)
  # Later than the wallet block the stub answers with by default, so a reading
  # taken before the transaction confirmed cannot pass for one taken after it.
  @receipt_block 1_249
  @refresh_failure "Refresh failed. The last confirmed Base snapshot remains on screen."
  @budget_refusal "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."

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
            :test_staking_denominator,
            :test_staking_protocol_error,
            :test_staking_wallet_error,
            :test_staking_paused,
            :test_staking_read_gate,
            :test_staking_read_at,
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

    assert html =~ "No Regent account or Privy login is required."
    assert html =~ "Staking active"
    assert has_element?(view, ".stake-total strong", "100")
    assert has_element?(view, ".stake-total span", "REGENT staked")
    assert has_element?(view, ".stake-benefit-card-primary", "12%")
    assert has_element?(view, ".stake-benefit-grid", "125,000.00 USDC")
    assert has_element?(view, ".stake-benefit-grid", "250k REGENT")
    assert html =~ "67k REGENT"
    assert html =~ "66.9k REGENT"
    assert html =~ "Base block #1,234"
    assert has_element?(view, ".stake-contract-facts dt", ~r/\ABase block\z/)
    assert html =~ @contract
    assert html =~ @regent
    assert html =~ @usdc

    assert has_element?(
             view,
             ~s(progress#staking-utilization[value="0.15"][max="100"][aria-label="Staking capacity utilization"])
           )

    assert has_element?(
             view,
             ~s(a[href="https://basescan.org/address/#{@contract}"][target="_blank"][rel="noopener noreferrer"]),
             "View verified staking contract on BaseScan"
           )

    assert has_element?(view, ~s(button[data-stake-connect]), "Connect wallet to stake")
    refute html =~ "Sign in for wallet access"

    for private_fact <- [
          "Available REGENT",
          "Currently staked",
          "Claimable USDC",
          "Claimable REGENT",
          @wallet
        ] do
      refute html =~ private_fact
    end

    refute has_element?(view, ".stake-wallet-summary")
    refute has_element?(view, "#staking-amount")
    refute has_element?(view, "button[data-staking-action]")
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
  end

  # The whole point of the shared reading: opening the page costs Base nothing.
  test "NO_READ_FOR_A_VISITOR: an anonymous visit with no wallet reads Base not at all", %{
    conn: conn
  } do
    seed_snapshot()
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    {:ok, view, _html} = live(conn, "/stake")
    assert has_element?(view, ".stake-total strong", "100")

    refute_receive {:staking_read, _scope, _reader}, 200
  end

  test "SNAPSHOT_AGE: the page says which block the contract data came from and how old it is", %{
    conn: conn
  } do
    Application.put_env(
      :ash_platform,
      :test_staking_read_at,
      DateTime.add(DateTime.utc_now(), -95, :second)
    )

    view = mount_stake(conn)

    assert has_element?(view, ".stake-snapshot-note", "Base block #1,234, read a minute ago")
  end

  test "PAUSED_SNAPSHOT: anonymous dashboard identifies a paused contract", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_paused, true)

    view = mount_stake(conn)
    html = render(view)

    assert html =~ "Staking paused"
    assert has_element?(view, ~s(.stake-contract-status[data-state="paused"]))
    assert has_element?(view, "#staking-utilization")
    assert html =~ "67k REGENT"
    refute has_element?(view, "button[data-staking-action]")
  end

  test "UNAVAILABLE_SNAPSHOT: with no shared reading the page offers an anonymous visitor no control",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/stake")
    html = render(view)

    assert html =~ "Staking details are unavailable right now."
    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    assert html =~ "A signed-in visitor can ask for a new reading."
    refute has_element?(view, ".stake-layout")
    refute has_element?(view, "#staking-utilization")
    refute has_element?(view, "button.stake-shared-refresh")
    refute html =~ @wallet
  end

  test "UNAVAILABLE_SNAPSHOT_SIGNED_IN: a signed-in visitor is offered the shared reading", %{
    conn: conn
  } do
    view = signed_in_stake(conn, "unavailable-shared")

    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    assert has_element?(view, "button.stake-shared-refresh", "Read the contract")
    refute render(view) =~ "A signed-in visitor can ask for a new reading."

    view |> element("button.stake-shared-refresh") |> render_click()
    assert render_async(view) =~ "Base block #1,234"
    assert has_element?(view, ".stake-total strong", "100")
  end

  test "SHARED_REFRESH_IS_SIGNED_IN_ONLY: an anonymous socket is refused server-side", %{
    conn: conn
  } do
    view = mount_stake(conn)
    refute has_element?(view, "button.stake-shared-refresh")

    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    # Far past every interval and allowance, so the only thing that can refuse
    # either event is the socket's own session. Without that guard the click
    # buys a reading for everybody.
    Application.put_env(:ash_platform, :staking_snapshot_clock, fn -> 10_000_000 end)

    render_hook(view, "refresh_shared_snapshot", %{})
    render_hook(view, "refresh_data", %{})

    refute_receive {:staking_read, _scope, _reader}, 200
    assert has_element?(view, ".stake-total strong", "100")
  end

  test "SHARED_REFRESH_BUDGET: a refusal says so in its own words, not as a Base failure", %{
    conn: conn
  } do
    seed_snapshot()
    view = conn |> signed_in_stake("shared-budget") |> activate(@wallet)
    assert has_element?(view, ".stake-total strong", "100")

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    html = render_async(view)

    assert html =~ @budget_refusal
    refute html =~ @refresh_failure

    # The Redeem page's own per-visitor lookup limit says something else
    # entirely; neither refusal can be mistaken for the other.
    refute html =~ "Owned NFT lookup is unavailable."
    assert has_element?(view, ".stake-total strong", "100")
  end

  # One control asks for both readings a person can want here: their own
  # position, which changes nothing for anyone else, and the contract reading,
  # which replaces what every visitor is shown. Each reading is labelled with
  # the block it was taken at, so one click has to move both blocks.
  test "REFRESH_DATA: one click reads this wallet's position and the contract everyone shares", %{
    conn: conn
  } do
    seed_snapshot()
    view = conn |> signed_in_stake("refresh-data") |> activate(@wallet)

    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert has_element?(view, ".stake-wallet-block", "Base block #1,240")
    assert has_element?(view, ".stake-snapshot-note", "Base block #1,234")

    Application.put_env(:ash_platform, :test_staking_wallet_block, @receipt_block)
    Application.put_env(:ash_platform, :test_staking_protocol_block, 9_876)

    on_exit(fn ->
      Application.delete_env(:ash_platform, :test_staking_wallet_block)
      Application.delete_env(:ash_platform, :test_staking_protocol_block)
    end)

    # Past every interval and allowance, so the shared reading this click asks
    # for is not turned away by the budget that guards it.
    Application.put_env(:ash_platform, :staking_snapshot_clock, fn -> 10_000_000 end)

    assert has_element?(
             view,
             ~s(.stake-footer button[phx-click="refresh_data"]),
             "Refresh Data"
           )

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

    # Someone else's refresh, announced to every page.
    share_new_snapshot()
    assert render_async(view) =~ "Base block #9,876"

    # The wallet map kept its own block and its own figures.
    assert has_element?(view, ".stake-wallet-block", "Base block #1,240")
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert render(view) =~ "5 REGENT"
  end

  test "TWO_BLOCKS: contract figures and wallet figures are labelled with their own blocks", %{
    conn: conn
  } do
    view = conn |> mount_stake() |> activate(@wallet)

    assert has_element?(view, ".stake-snapshot-note", "Base block #1,234")
    assert has_element?(view, ".stake-wallet-block", "Base block #1,240")
    assert TestStakingChainClient.wallet_block() != TestStakingChainClient.protocol_block()
  end

  # A confirmed transaction is only visible from the block its receipt was mined
  # into. The refresh the browser pushes the moment a receipt confirms therefore
  # takes a fresh block of its own; answering it from the remembered contract
  # block would show the person their position from before their own
  # transaction and leave them staring at a figure that never moves.
  test "POST_CONFIRMATION_REFRESH: the wallet is re-read at the receipt's block, not the cached one",
       %{conn: conn} do
    view = conn |> mount_stake() |> activate(@wallet)

    assert staking_assigns(view).staking.wallet_block_number ==
             TestStakingChainClient.wallet_block()

    # The transaction confirms, and Base now answers about this wallet at the
    # block the receipt was mined into.
    Application.put_env(:ash_platform, :test_staking_wallet_block, @receipt_block)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_wallet_block) end)

    # Exactly what the browser pushes once it has a confirmed receipt.
    render_hook(view, "refresh_staking", %{})
    render_async(view)

    staking = staking_assigns(view).staking
    assert staking.wallet_block_number == @receipt_block
    assert staking.wallet_block_number > TestStakingChainClient.wallet_block()
    assert has_element?(view, ".stake-wallet-block", "Base block #1,249")

    # The contract figures keep the block they were read at, and the one reading
    # every visitor shares was not replaced by this wallet's lookup.
    assert staking.block_number == TestStakingChainClient.protocol_block()
    assert SnapshotCache.snapshot().block_number == TestStakingChainClient.protocol_block()
    assert has_element?(view, ".stake-snapshot-note", "Base block #1,234")
  end

  test "ANONYMOUS_ACTIVE_WALLET: any connected wallet can use staking without Regent login", %{
    conn: conn
  } do
    view = mount_stake(conn)
    assert has_element?(view, "button[data-stake-connect]")
    refute has_element?(view, "#staking-amount")

    activate(view, @other)
    assert has_element?(view, "#staking-amount")
    assert has_element?(view, ~s(#regent-staking[data-staking-signer="#{@other}"]))

    activate(view, @wallet)
    assert has_element?(view, "#staking-amount")
    html = render(view)
    assert has_element?(view, ".stake-wallet-summary")
    assert html =~ "Currently staked"
    assert html =~ "Claimable REGENT"
    assert html =~ "5 REGENT"
    assert has_element?(view, ~s(#account-control button[data-account-target="sign-in"]))
  end

  test "DIRECT_STAKE: canonical browser data renders without a server preparation event", %{
    conn: conn
  } do
    view = conn |> mount_stake() |> activate(@wallet)
    set_amount(view, "1")

    assert has_element?(
             view,
             ~s(#regent-staking[data-staking-chain-id="8453"][data-staking-signer="#{@wallet}"][data-staking-allowance="0"])
           )

    assert has_element?(view, "#regent-staking > #staking-result-dialog[phx-update=ignore]")
    assert has_element?(view, ~s(button[data-staking-action="stake"]))
    refute has_element?(view, "[phx-click=prepare_staking]")
    refute_push_event(view, "staking:wallet-action", _)

    html = render(view)

    for retired <- ["Review before signing", "Submitted transaction", "transaction hash", "Retry"] do
      refute html =~ retired
    end
  end

  test "ALLOWANCE_SNAPSHOT: the rendered routing hint is read-only browser data",
       %{
         conn: conn
       } do
    view = conn |> mount_stake() |> activate(@wallet)

    assert has_element?(view, ~s(#regent-staking[data-staking-allowance="0"]))
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "EXACT_LABELS: all eligible direct actions use the specified control copy", %{conn: conn} do
    view = conn |> mount_stake() |> activate(@wallet)

    for label <- ["Stake REGENT", "Unstake", "Claim USDC", "Claim REGENT", "Claim and restake"] do
      assert has_element?(view, "button", label)
    end
  end

  test "AMOUNT_LIMITS: Max follows capacity and an over-limit amount still reaches the wallet", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "105000000000000000000")
    view = conn |> mount_stake() |> activate(@wallet)

    view |> element(~s(button[phx-value-portion="max"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="5"]))

    set_amount(view, "5.000000000000000001")
    assert render(view) =~ "more REGENT than the staking contract can still take"
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)

    set_amount(view, "11")
    assert render(view) =~ "That is more REGENT than this wallet holds"
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "CLAIM_HINTS: every claim stays clickable and the reading only explains itself", %{
    conn: conn
  } do
    view = conn |> mount_stake() |> activate(@wallet)

    assert_every_claim_live(view)
    refute render(view) =~ "in the last reading from Base"

    reread(view, %{usdc_claimable: "0"})
    assert_every_claim_live(view)
    assert_hint(view, "claim_usdc", "Claim USDC — no USDC rewards in the last reading from Base.")

    reread(view, %{regent_claimable: "0", regent_funded: "0"})
    assert_every_claim_live(view)

    assert_hint(
      view,
      "claim_regent",
      "Claim REGENT — no REGENT rewards accrued in the last reading from Base."
    )

    assert_hint(
      view,
      "claim_and_restake_regent",
      "Claim and restake — no REGENT rewards accrued in the last reading from Base."
    )

    reread(view, %{regent_claimable: "2000000000000000000", regent_funded: "1000000000000000000"})
    assert_every_claim_live(view)

    assert_hint(
      view,
      "claim_regent",
      "the funded REGENT reward inventory is below what is claimable in the last reading from Base."
    )

    # Capacity is a contract limit, so this hint only moves once the shared
    # reading does; the wallet reading alone never changes it.
    Application.put_env(:ash_platform, :test_staking_denominator, "101000000000000000000")
    share_new_snapshot()
    reread(view, %{})
    assert_every_claim_live(view)

    assert_hint(
      view,
      "claim_and_restake_regent",
      "restaking the claimable REGENT exceeds the capacity the contract can still take in the last reading from Base."
    )

    Application.put_env(:ash_platform, :test_staking_paused, true)
    share_new_snapshot()
    reread(view, %{})
    assert_every_claim_live(view)

    assert_hint(
      view,
      "claim_and_restake_regent",
      "Claim and restake — staking shows as paused in the last reading from Base."
    )
  end

  test "REFRESH_ONLY: refreshing rereads Base without any wallet request", %{conn: conn} do
    view = conn |> mount_stake() |> activate(@wallet)
    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "IN_PLACE_REFRESH: confirmed facts and actions remain visible while Base is reread", %{
    conn: conn
  } do
    swap_client(GatedChainClient)

    view = conn |> mount_stake() |> activate(@wallet)
    set_amount(view, "1")
    Application.put_env(:ash_platform, :test_staking_read_gate, self())

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    assert_receive {:staking_read_waiting, read}

    assert has_element?(view, ~s(#regent-staking[aria-busy="true"]))
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-total strong", "100")
    assert has_element?(view, ".stake-total span", "REGENT staked")
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert has_element?(view, ~s(#staking-amount[value="1"]))
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
    assert has_element?(view, ".stake-inline-loading", "Updating from Base…")

    Application.delete_env(:ash_platform, :test_staking_read_gate)
    send(read, :continue_staking_read)
    render_async(view)

    refute has_element?(view, ~s(#regent-staking[aria-busy="true"]))
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
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

  test "FIRST_WALLET_READ_FAILURE: contract data stays visible with recovery controls", %{
    conn: conn
  } do
    view = mount_stake(conn)
    Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)

    render_hook(view, "staking_active_wallet", %{"address" => @wallet})
    render_async(view)

    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-wallet-recovery", "Try again")
    refute has_element?(view, ".stake-wallet-loading")
  end

  # A second wallet arrives while the first wallet's read is still open, so that
  # read is cancelled and replaced. A cancelled read reported nothing about
  # Base and must not be mistaken for a failed one.
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
    assert has_element?(view, ".stake-total strong", "100")

    Application.delete_env(:ash_platform, :test_staking_read_gate)
    send(second_read, :continue_staking_read)
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert render(view) =~ @wallet
  end

  # A wallet read that genuinely crashed leaves the contract data alone and
  # offers the wallet its own way back.
  test "WALLET_READ_CRASH: a crashed wallet read keeps the contract data and recovers", %{
    conn: conn
  } do
    view = mount_stake(conn)
    swap_client(CrashingChainClient)

    render_hook(view, "staking_active_wallet", %{"address" => @wallet})
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-wallet-recovery", "Try again")
    assert render(view) =~ @refresh_failure
  end

  # A wallet reading carries no contract figures, so with no contract reading on
  # the server there is nothing to show it beside. The page says so and buys
  # nothing rather than spending four round trips on an answer it would discard.
  test "COLD_START_WALLET: connecting a wallet with no contract reading buys no chain read", %{
    conn: conn
  } do
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_read_watcher) end)

    {:ok, view, _html} = live(conn, "/stake")
    render_hook(view, "staking_active_wallet", %{"address" => @wallet})

    refute_receive {:staking_read, _scope, _reader}, 200
    assert staking_assigns(view).staking_status == :error

    # The page never claims to be loading something nobody asked Base for, and
    # an anonymous visitor is told who can put it right.
    html = render(view)
    assert html =~ "Staking details are unavailable right now."
    assert html =~ "A signed-in visitor can ask for a new reading."
    refute html =~ "Loading staking contract data"
    refute has_element?(view, ".stake-wallet-summary")

    # Once a reading exists, the wallet already connected is looked up.
    share_new_snapshot()
    view |> element(~s(button[phx-click="refresh_staking"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
  end

  test "REFRESH_NOTICE_SCOPE: a successful read preserves an unrelated notice" do
    name = {:staking, 7}
    notice = %{tone: :error, message: "An unrelated wallet action notice."}

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        content_generation: 7,
        staking: %{total_staked: "100"},
        staking_notice: notice,
        staking_read: %{name: name}
      }
    }

    assert {:noreply, updated} =
             ShellLive.handle_async(
               name,
               {:ok, {7, {:ok, %{wallet_stake_balance: "5"}}}},
               socket
             )

    assert updated.assigns.staking_notice == notice
    assert updated.assigns.staking_status == :ready
    assert updated.assigns.staking == %{total_staked: "100", wallet_stake_balance: "5"}
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

    # The transaction was still sent, so the repeat is answered rather than left
    # waiting on a result that would never arrive.
    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :unavailable
    })

    send(observer, {:wallet_observation_result, :success})
    render_async(view)
  end

  # Every observation polls Base for up to two minutes, so a page that keeps
  # pushing cannot keep buying chain reads.
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

    # A settled observation gives its place back, so the cap bounds live work
    # rather than retiring the page.
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

    # The same id is observable again, which is only true if the crashed
    # observation gave its place back.
    render_hook(view, "observe_staking_transaction", observation("obs-1"))
    assert_receive {:wallet_observation, :staking, _transaction, retried}

    send(retried, {:wallet_observation_result, :success})
    render_async(view)

    assert_push_event(view, "staking:transaction-result", %{
      observation_id: "obs-1",
      result: :success
    })
  end

  # An exported ASH_PLATFORM_BROWSER_TEST must not swap the browser observer,
  # which confirms every well-formed hash, into an ExUnit run.
  test "OBSERVATION_STUB_IS_NOT_DEFAULTING: ExUnit observes through the watcher-driven stub" do
    assert Application.get_env(:ash_platform, :wallet_transaction_observer) ==
             AshPlatform.TestWalletTransactionObserver

    assert AshPlatform.TestWalletTransactionObserver.observe(%{"hash" => @hash}, :staking) ==
             :unavailable
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
      "to" => @contract,
      "data" => "0xa9059cbb"
    }

  defp assert_every_claim_live(view) do
    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent) do
      assert has_element?(view, ~s|button[data-staking-action="#{action}"]:not([disabled])|)
    end

    refute has_element?(view, "button[data-staking-action][disabled]")
  end

  defp assert_hint(view, action, copy) do
    assert has_element?(
             view,
             ~s|button[data-staking-action="#{action}"][aria-describedby="staking-claim-hint-#{action}"]|
           )

    assert has_element?(view, "p#staking-claim-hint-#{action}", copy)
  end

  defp reread(view, balances) do
    Application.put_env(:ash_platform, :test_staking_balances, %{@wallet => balances})
    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)
    view
  end

  defp set_amount(view, amount),
    do: view |> form("#staking-amount-form", %{"amount" => amount}) |> render_change()

  # The shared reading exists before anyone opens the page, exactly as it does
  # in production after the server's own first read.
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

  defp staking_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp activate(view, wallet) do
    render_hook(view, "staking_active_wallet", %{"address" => wallet})
    render_async(view)
    view
  end
end
