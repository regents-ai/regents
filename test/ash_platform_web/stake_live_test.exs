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
  # Every control on this page that ends in a wallet request, by the copy it
  # carries. The submit control names whichever mode is selected.
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

    assert html =~ "Staking active"
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
    assert has_element?(view, ".stake-supply-facts dt", "Total staked")

    # The hero is exactly the two cards the contract answers for: what Regent
    # Labs earned, over seven days and over its lifetime, and what is staked.
    assert has_element?(view, ".stake-benefit-card-primary dt", "Regent Labs USDC Earned")
    assert has_element?(view, ".stake-earned-part", "Last 7 days")
    assert has_element?(view, ".stake-earned-part", "Lifetime")
    assert has_element?(view, ".stake-benefit-card-primary", "1,250.50 USDC")
    assert has_element?(view, ".stake-benefit-card-primary", "5,074.87 USDC")
    assert has_element?(view, ".stake-benefit-card dt", "REGENT Staked")
    assert has_element?(view, ".stake-benefit-grid", "100 REGENT")

    # The emissions APR is no longer one of them, though the contract's own
    # figure still explains why staking earns REGENT at all.
    refute has_element?(view, ".stake-benefit-grid", "12%")
    assert has_element?(view, ".stake-how-it-works", "12% emissions APR")

    # The supply block: the three figures and the one proportion it names.
    assert has_element?(view, "#staking-supply-bar")
    assert has_element?(view, ".stake-supply-facts dt", "Total staked")
    assert has_element?(view, ".stake-supply-facts dt", "Circulating supply")
    assert has_element?(view, ".stake-supply-facts dt", "Total supply")
    assert has_element?(view, ".stake-supply-facts", "35 billion REGENT")
    assert has_element?(view, ".stake-supply-facts", "100 billion REGENT")
    assert has_element?(view, ".stake-supply-heading", "% of circulating supply staked")
    assert html =~ "Base block #1,234"
    assert has_element?(view, ".stake-contract-facts dt", ~r/\ABase block\z/)
    assert html =~ @contract
    assert html =~ @regent
    assert html =~ @usdc

    assert has_element?(
             view,
             ~s(a[href="https://basescan.org/address/#{@contract}"][target="_blank"][rel="noopener noreferrer"]),
             "View verified staking contract on BaseScan"
           )

    assert has_element?(
             view,
             ~s|button.stake-primary[data-account-target="sign-in"]|,
             "Connect wallet to stake"
           )

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

  # The hero says how much REGENT exists and how much of it moves, both to the
  # four digits a person reads and to the exact figure on hover.
  test "HERO_SUPPLY: the hero carries circulating and total REGENT", %{conn: conn} do
    view = mount_stake(conn)

    assert has_element?(view, ".stake-benefit-supply dt", "Circulating REGENT")
    assert has_element?(view, ".stake-benefit-supply dt", "Total REGENT")
    assert has_element?(view, ".stake-benefit-supply", "35 billion")
    assert has_element?(view, ".stake-benefit-supply", "100 billion")

    # The circulating figure moves, so its exact form is two decimals rather
    # than the eighteen the chain keeps it in. The supply is a whole number.
    assert has_element?(view, ~s(.stake-benefit-supply [title="35,000,000,000.00"]))
    assert has_element?(view, ~s(.stake-benefit-supply [title="100,000,000,000"]))
  end

  # Where the USDC comes from is read before what the contract currently holds,
  # and every source is closed until somebody opens it.
  test "REVENUE_SOURCES: the four products and their streams are listed above the position", %{
    conn: conn
  } do
    view = mount_stake(conn)
    html = render(view)

    assert has_element?(view, "#staking-revenue-sources h2", "USDC Revenue Sources")

    position = :binary.match(html, "staking-revenue-sources")
    overview = :binary.match(html, "staking-contract-overview")
    assert elem(position, 0) < elem(overview, 0)

    for {product, streams} <- [
          {"Regents Labs",
           [
             "REGENT/ETH Uniswap v4 Pool Fee (0.1-0.3% on volume)",
             "Protocol x402 Services"
           ]},
          {"Autolaunch",
           [
             "All Tokens Uniswap v4 Hooks (1% on volume)",
             "All Tokens USDC Revenue (2% on volume)"
           ]},
          {"Techtree", ["Paid Artifact Revenue (5% on volume)", "Protocol Environment Revenue"]},
          {"Patchbay", ["Priority Question Revenue (10% on volume)"]}
        ] do
      assert has_element?(view, ".stake-revenue-source > summary", product)
      for stream <- streams, do: assert(has_element?(view, ".stake-revenue-source li", stream))
    end

    assert view |> element("#staking-revenue-sources") |> render() =~ "<details"
    refute view |> element("#staking-revenue-sources") |> render() =~ "open"
  end

  # The whole point of the shared reading: opening the page costs Base nothing.
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

  # A week in which the contract recorded nothing is a figure like any other.
  # Writing anything else there would invite a reader to supply their own number.
  test "ZERO_IS_A_FIGURE: a seven-day window with no deposits reads 0.00 USDC", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_usdc_7d, "0")

    view = mount_stake(conn)

    assert has_element?(view, ".stake-earned-part", "Last 7 days")
    assert has_element?(view, ".stake-benefit-card-primary", "0.00 USDC")
    assert has_element?(view, ".stake-benefit-card-primary", "5,074.87 USDC")
    refute render(view) =~ "yet"
  end

  # The seven-day window is read from the contract's own log history rather than
  # from its current answers, so an endpoint that refuses that history has said
  # nothing about anything else on the page. One figure goes missing and says so;
  # everything else, and every control, is exactly where it was.
  test "UNAVAILABLE_WINDOW: a missing seven-day figure costs nothing else on the page", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_usdc_7d, :unavailable)

    view = stake_as_signer(conn, "unavailable-window")

    assert staking_assigns(view).staking_status == :ready
    refute render(view) =~ "Staking details are unavailable right now."

    # The one figure that was lost says so, in words rather than as a zero.
    assert has_element?(view, ".stake-earned-part", "Last 7 days")

    assert has_element?(
             view,
             ".stake-benefit-card-primary .figure-unavailable",
             "Unavailable right now"
           )

    refute has_element?(view, ".stake-benefit-card-primary", "0.00 USDC")

    # Every other figure on the page is there and exact.
    assert has_element?(view, ".stake-benefit-card-primary", "5,074.87 USDC")
    assert has_element?(view, ".stake-benefit-card", "100 REGENT")
    assert has_element?(view, "#staking-supply-bar")
    assert has_element?(view, ".stake-supply-facts", "35 billion REGENT")
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-contract-facts", @contract)

    # Every control still reaches the wallet, and the refresh path stays open.
    assert_every_claim_live(view)
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)
    assert has_element?(view, ~s|button[phx-value-portion="max"]:not([disabled])|)

    # The next reading that gets the window puts the figure back.
    Application.delete_env(:ash_platform, :test_staking_usdc_7d)
    share_new_snapshot()
    render_async(view)
    assert has_element?(view, ".stake-benefit-card-primary", "1,250.50 USDC")
    refute has_element?(view, ".figure-unavailable")
  end

  # The whole-page notice belongs to one failure and one only: the contract
  # reading itself. A page that has never had one shows nothing but the notice.
  test "CORE_READING_FAILS: only a failed contract reading empties the page", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)

    view = signed_in_stake(conn, "core-reading-fails")

    assert staking_assigns(view).staking_status == :error
    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    refute has_element?(view, ".stake-layout")
    refute has_element?(view, "button[data-staking-action]")

    # The one control this state offers is the reading itself, and once that
    # reading lands the page is whole again.
    assert has_element?(view, "button.stake-shared-refresh", "Read the contract")
    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    view |> element("button.stake-shared-refresh") |> render_click()
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
    refute render(view) =~ "Staking details are unavailable right now."
  end

  # One bar carries both proportions, and each is the arithmetic of the figures
  # beside it rather than anything the page decides.
  test "SUPPLY_SHARES: the bar and its label follow the three supply figures", %{conn: conn} do
    view = mount_stake(conn)

    # 100 REGENT staked is nothing against 35 billion circulating, and that 35
    # billion is 35% of the 100 billion the token reports.
    assert render(view) =~ "--circulating-share: 35%; --staked-share: 0%"

    assert has_element?(
             view,
             ~s(#staking-supply-bar[aria-label="0% of circulating supply staked, and 35% of total supply circulating"])
           )

    # The same page against a circulating supply the staked figure can be seen
    # against: 100 of 500 REGENT.
    put_circulating("500000000000000000000")
    view = mount_stake(conn)

    assert has_element?(view, ".stake-supply-heading", "20% of circulating supply staked")
    assert render(view) =~ "--staked-share: 20%"
  end

  # 100 REGENT staked of 3,200 circulating is exactly 3.125%, the halfway case a
  # rounded figure would overstate. The share is cut to two decimals like every
  # other figure here, so the page says 3.12% and never 3.13%.
  test "SUPPLY_SHARE_TRUNCATES: a share landing halfway is cut rather than rounded up", %{
    conn: conn
  } do
    put_circulating("3200000000000000000000")

    view = mount_stake(conn)
    html = render(view)

    assert has_element?(view, ".stake-supply-heading", "3.12% of circulating supply staked")
    assert html =~ "--staked-share: 3.12%"
    refute html =~ "3.13"
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
    assert has_element?(view, "#staking-supply-bar")
    assert has_element?(view, ".stake-supply-facts", "35 billion REGENT")
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
    refute has_element?(view, "#staking-supply-bar")
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
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
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

    # The Redeem page's own per-visitor lookup limit says something else
    # entirely; neither refusal can be mistaken for the other.
    refute html =~ "Owned NFT lookup is unavailable."
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
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

  test "ANONYMOUS_ACTIVE_WALLET: any connected wallet is read without a Regent login", %{
    conn: conn
  } do
    view = mount_stake(conn)
    assert has_element?(view, ~s|button.stake-primary[data-account-target="sign-in"]|)
    refute has_element?(view, "#staking-amount")

    activate(view, @other)
    assert has_element?(view, "#staking-amount")

    activate(view, @wallet)
    assert has_element?(view, "#staking-amount")
    html = render(view)
    assert has_element?(view, ".stake-wallet-summary")
    assert html =~ "Currently staked"
    assert html =~ "Claimable REGENT"
    assert html =~ "5 REGENT"
    assert has_element?(view, ~s(#account-control button[data-account-target="sign-in"]))
  end

  test "SIGN_IN_BEFORE_SENDING: a wallet with no sign-in reads its position and sends nothing", %{
    conn: conn
  } do
    view = conn |> mount_stake() |> activate(@wallet)

    # Reading this wallet is open to everyone.
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    assert_offers_sign_in(view)
  end

  test "WALLET_MISMATCH: a sign-in on one wallet cannot send from another", %{conn: conn} do
    view = stake_as_signer(conn, "wallet-mismatch")

    # The wallet the sign-in names can send.
    assert has_element?(view, ~s(#regent-staking[data-staking-signer="#{@wallet}"]))
    assert has_element?(view, ~s|button[data-staking-action="stake"]|)

    # The browser switches to a wallet this account never signed in with.
    activate(view, @other)
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    assert_refuses_every_action(
      view,
      "You must disconnect 0x1111…1111 and connect again with wallet address 0x2222…2222."
    )

    # Switching back to the wallet the sign-in names restores every action.
    activate(view, @wallet)
    assert has_element?(view, ~s(#regent-staking[data-staking-signer="#{@wallet}"]))
    assert has_element?(view, ~s|button[data-staking-action="stake"]|)
    refute render(view) =~ "You must disconnect"
  end

  test "REFUSAL_IS_ONLY_A_REFUSAL: the event changes nothing when there is nothing to refuse", %{
    conn: conn
  } do
    for view <- [conn |> mount_stake() |> activate(@wallet), stake_as_signer(conn, "no-refusal")] do
      # A notice the visitor is already reading, put there by something else.
      Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)
      view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
      render_async(view)
      Application.delete_env(:ash_platform, :test_staking_wallet_error)
      assert render(view) =~ @refresh_failure

      # The page only sends this event while the wallets disagree. A browser
      # sending it anyway has nothing refused and wipes nothing.
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
    assert has_element?(view, ".stake-wallet-summary")

    # Exactly what the browser pushes once Disconnect has released every wallet.
    activate(view, nil)

    assigns = staking_assigns(view)
    assert assigns.staking_wallet == nil
    assert assigns.staking_amount == ""

    for key <- AshPlatform.Staking.Facts.wallet_keys() do
      assert Map.fetch!(assigns.staking, key) == nil
    end

    html = render(view)
    assert has_element?(view, ~s|button.stake-primary[data-account-target="sign-in"]|)
    refute has_element?(view, "#staking-amount")
    refute has_element?(view, ".stake-wallet-summary")
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    refute html =~ "Currently staked"
    refute html =~ @refresh_failure

    # The contract figures every visitor shares stay exactly where they were.
    assert has_element?(view, ".stake-benefit-grid", "100 REGENT")
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
    view = stake_as_signer(conn, "allowance-snapshot")

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
    view = stake_as_signer(conn, "amount-limits")

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

  test "REVENUE_SHARE: the preview reads a staker's share of revenue against the whole supply", %{
    conn: conn
  } do
    # Revenue is accounted against the whole 100 billion REGENT supply, so this
    # figure is the position over that supply, never over the staked pool.
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

    # Four places are always shown, and the fifth is dropped rather than rounded
    # up, so the figure never claims more than the position earns.
    set_amount(view, "89999999")
    assert render(view) =~ "1.5899%"

    view |> element(~s(button[phx-value-mode="unstake"])) |> render_click()
    set_amount(view, "500000000")
    assert render(view) =~ "1.0000%"
  end

  test "CLAIM_GLOW: every claim stays clickable and only a reward that is there is lit", %{
    conn: conn
  } do
    view = stake_as_signer(conn, "claim-hints")

    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_usdc claim_regent claim_and_restake_regent)

    # The glow is a colour, so each control also says in its own name whether
    # there is anything to take.
    assert claim_name(view, "claim_usdc") == "Claim USDC (available)"
    assert claim_name(view, "claim_regent") == "Claim REGENT (available)"
    assert claim_name(view, "claim_and_restake_regent") == "Claim and restake (available)"

    reread(view, %{usdc_claimable: "0"})
    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_regent claim_and_restake_regent)

    reread(view, %{regent_claimable: "0", regent_funded: "0"})
    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_usdc)
    assert claim_name(view, "claim_usdc") == "Claim USDC (available)"
    assert claim_name(view, "claim_regent") == "Claim REGENT (nothing to claim)"
    assert claim_name(view, "claim_and_restake_regent") == "Claim and restake (nothing to claim)"

    reread(view, %{regent_claimable: "2000000000000000000", regent_funded: "1000000000000000000"})
    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_usdc)

    # Capacity is a contract limit, so compounding only goes dark once the shared
    # reading moves; the wallet reading alone never changes it.
    Application.put_env(:ash_platform, :test_staking_denominator, "101000000000000000000")
    share_new_snapshot()
    reread(view, %{})
    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_usdc claim_regent)

    Application.put_env(:ash_platform, :test_staking_paused, true)
    share_new_snapshot()
    reread(view, %{})
    assert_every_claim_live(view)
    assert lit_claims(view) == ~w(claim_usdc claim_regent)

    # The row is buttons alone: the reading is shown by which of them is lit.
    refute render(view) =~ "in the last reading from Base"
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

    view = stake_as_signer(conn, "in-place-refresh")
    set_amount(view, "1")
    Application.put_env(:ash_platform, :test_staking_read_gate, self())

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    assert_receive {:staking_read_waiting, read}

    assert has_element?(view, ~s(#regent-staking[aria-busy="true"]))
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
    assert has_element?(view, ".stake-supply-facts dt", "Total staked")
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

  # A position nobody could read is that wallet's figures and nothing else. The
  # contract data stays, the wallet's own section stays, each of its figures says
  # it is missing, and every control on it still reaches the wallet.
  test "FIRST_WALLET_READ_FAILURE: only this wallet's figures go missing", %{conn: conn} do
    view = stake_as_signer(conn, "first-wallet-failure")
    Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)

    view |> element(~s(.stake-footer button[phx-click="refresh_data"])) |> render_click()
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-overview", "Live contract position")
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")
    assert has_element?(view, ".stake-benefit-card", "1,250.50 USDC")
    refute has_element?(view, ".stake-wallet-loading")

    # The wallet's own section is still there, saying which figures it lost.
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")

    assert has_element?(
             view,
             ".stake-wallet-summary .figure-unavailable",
             "Unavailable right now"
           )

    assert has_element?(view, ".stake-wallet-block", "could not be read just now")
    refute render(view) =~ "Staking details are unavailable right now."

    # Every control that ends in a wallet request is still live.
    assert_every_claim_live(view)
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)

    # An amount the page cannot check against a missing figure is still sent.
    set_amount(view, "3")
    assert render(view) =~ "this amount is not checked against it"
    assert has_element?(view, ~s|button[data-staking-action="stake"]:not([disabled])|)

    # With no allowance to go by, the browser is told to expect the approval
    # step rather than the press being held back.
    refute has_element?(view, "#regent-staking[data-staking-allowance]")
    assert render(view) =~ "will first request an exact REGENT approval"
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
    assert has_element?(view, ".stake-supply-facts", "100 REGENT")

    Application.delete_env(:ash_platform, :test_staking_read_gate)
    send(second_read, :continue_staking_read)
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-wallet-summary", "Currently staked")
    assert render(view) =~ @wallet
  end

  # A wallet read that genuinely crashed is the same news as one that failed.
  test "WALLET_READ_CRASH: a crashed wallet read keeps every other figure and control", %{
    conn: conn
  } do
    view = mount_stake(conn)
    swap_client(CrashingChainClient)

    render_hook(view, "staking_active_wallet", %{"address" => @wallet})
    render_async(view)

    assert staking_assigns(view).staking_status == :ready
    assert has_element?(view, ".stake-overview", "Live contract position")

    assert has_element?(
             view,
             ".stake-wallet-summary .figure-unavailable",
             "Unavailable right now"
           )

    assert has_element?(view, ~s(.stake-footer button[phx-click="refresh_data"]))
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

  defp claim_name(view, action) do
    view
    |> element(~s|button[data-staking-action="#{action}"]|)
    |> render()
    |> String.replace(~r/<[^>]*>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp lit_claims(view) do
    for action <- ~w(claim_usdc claim_regent claim_and_restake_regent),
        has_element?(view, ~s|button[data-staking-action="#{action}"].stake-claim-ready|),
        do: action
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

  # The Stake page as someone who may send a transaction sees it: signed in, with
  # the browser's active wallet being the one that sign-in names.
  defp stake_as_signer(conn, suffix) do
    seed_snapshot()
    conn |> signed_in_stake(suffix) |> activate(@wallet)
  end

  # Every control that ends in a wallet request answers with the same refusal,
  # and the page carries nothing a transaction could be built from.
  # With nobody signed in, every control that would end in a wallet request is
  # the Privy sign-in instead, and the page carries nothing a transaction could
  # be built from.
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

  # A test that wants a different circulating supply sets what the stubbed chain
  # reports and puts the previous figure back.
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
