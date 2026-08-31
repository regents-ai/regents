defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatformWeb.ShellLive

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @contract "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
  @regent "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  @usdc "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"

  setup do
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
            :test_staking_overview_error,
            :test_staking_paused
          ] do
        Application.delete_env(:ash_platform, key)
      end
    end)

    :ok
  end

  defmodule CrashingChainClient do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def overview(_wallet), do: exit(:simulated_refresh_crash)

    @impl true
    def allowance(_wallet, _amount), do: {:ok, :insufficient}
  end

  test "PUBLIC_FACTS: anonymous visitors see current Base facts and no wallet controls", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert html =~ "Public contract data is available without signing in."
    assert html =~ "Staking active"
    assert html =~ "Total staked"
    assert has_element?(view, ".stake-total strong", "100")
    assert has_element?(view, ".stake-total span", "REGENT")
    assert html =~ "67,000 REGENT"
    assert html =~ "66,900 REGENT"
    assert html =~ "Base safe block #1,234"
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

    assert html =~ "Browsing contract data needs no sign-in."

    assert has_element?(
             view,
             ~s(button[data-account-target="sign-in"]),
             "Sign in for wallet access"
           )

    for private_fact <- [
          "Wallet balance",
          "Wallet stake",
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

  test "PAUSED_SNAPSHOT: anonymous dashboard identifies a paused contract", %{conn: conn} do
    Application.put_env(:ash_platform, :test_staking_paused, true)

    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert html =~ "Staking paused"
    assert has_element?(view, ~s(.stake-contract-status[data-state="paused"]))
    assert has_element?(view, "#staking-utilization")
    assert html =~ "67,000 REGENT"
    refute has_element?(view, "button[data-staking-action]")
  end

  test "UNAVAILABLE_SNAPSHOT: failed public reads expose no dashboard or wallet data", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_overview_error, :provider_failure)

    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)

    assert html =~ "Staking details are unavailable right now."
    assert has_element?(view, ~s(p[role="alert"]), "Staking details are unavailable right now.")
    refute has_element?(view, ".stake-layout")
    refute has_element?(view, "#staking-utilization")
    refute html =~ @wallet
  end

  test "ACTIVE_WALLET_ONLY: private facts require a linked active wallet", %{conn: conn} do
    account = register("stake-wallet", [@wallet])
    view = mount_stake(conn, account)
    render_async(view)
    assert has_element?(view, "button[data-stake-connect]")
    refute has_element?(view, "#staking-amount")

    activate(view, @other)
    render_async(view)
    assert render_async(view) =~ "not one of the wallets on your Regent account"
    refute has_element?(view, "#staking-amount")

    activate(view, @wallet)
    assert has_element?(view, "#staking-amount")
    html = render(view)
    assert has_element?(view, ".stake-wallet-summary")
    assert html =~ "Wallet stake"
    assert html =~ "Claimable REGENT"
    assert html =~ "5 REGENT"
    refute html =~ "Currently funded REGENT"
  end

  test "DIRECT_STAKE: canonical browser data renders without a server preparation event", %{
    conn: conn
  } do
    view = conn |> signed_in("stake-direct") |> activate(@wallet)
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
    view = conn |> signed_in("stake-allowance") |> activate(@wallet)

    assert has_element?(view, ~s(#regent-staking[data-staking-allowance="0"]))
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "EXACT_LABELS: all eligible direct actions use the specified control copy", %{conn: conn} do
    view = conn |> signed_in("stake-labels") |> activate(@wallet)

    for label <- ["Stake", "Unstake", "Claim USDC", "Claim REGENT", "Claim and restake"] do
      assert has_element?(view, "button", label)
    end
  end

  test "AMOUNT_LIMITS: Max follows current capacity without becoming a send-time lock", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_denominator, "105000000000000000000")
    view = conn |> signed_in("stake-limits") |> activate(@wallet)

    view |> element(~s(button[phx-value-portion="max"])) |> render_click()
    assert has_element?(view, ~s(#staking-amount[value="5"]))

    set_amount(view, "5.000000000000000001")
    assert render(view) =~ "more REGENT than the staking contract can still take"
    refute has_element?(view, ~s(button[data-staking-action="stake"][disabled]))
  end

  test "REFRESH_ONLY: refreshing rereads Base without any wallet request", %{conn: conn} do
    view = conn |> signed_in("stake-refresh") |> activate(@wallet)
    view |> element(~s(button[phx-click="refresh_staking"])) |> render_click()
    render_async(view)
    refute_push_event(view, "staking:wallet-action", _)
  end

  test "REFRESH_FAILURE: failed and crashed refreshes preserve the last snapshot", %{conn: conn} do
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)
    on_exit(fn -> Application.put_env(:ash_platform, :staking_chain_client, previous_client) end)

    view = conn |> signed_in("stake-refresh-failure") |> activate(@wallet)
    Application.put_env(:ash_platform, :test_staking_overview_error, :provider_failure)
    view |> element(~s(button[phx-click="refresh_staking"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Total staked")
    assert render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    Application.delete_env(:ash_platform, :test_staking_overview_error)
    Application.put_env(:ash_platform, :staking_chain_client, CrashingChainClient)
    view |> element(~s(button[phx-click="refresh_staking"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Total staked")
    assert render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."

    Application.put_env(:ash_platform, :staking_chain_client, previous_client)
    view |> element(~s(button[phx-click="refresh_staking"])) |> render_click()
    render_async(view)

    assert has_element?(view, ".stake-overview", "Total staked")
    refute render(view) =~ "Refresh failed. The last confirmed Base snapshot remains on screen."
  end

  test "REFRESH_NOTICE_SCOPE: a successful read preserves an unrelated notice" do
    name = {:staking, 7}
    notice = %{tone: :error, message: "An unrelated wallet action notice."}

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        content_generation: 7,
        staking_notice: notice,
        staking_read: %{name: name}
      }
    }

    assert {:noreply, updated} =
             ShellLive.handle_async(name, {:ok, {7, {:ok, %{total_staked: "100"}}}}, socket)

    assert updated.assigns.staking_notice == notice
    assert updated.assigns.staking_status == :ready
  end

  defp set_amount(view, amount),
    do: view |> form("#staking-amount-form", %{"amount" => amount}) |> render_change()

  defp register(suffix, wallets) do
    {:ok, account} =
      Accounts.register_verified("did:privy:#{suffix}", hd(wallets), wallets, actor: %System{})

    account
  end

  defp signed_in(conn, suffix), do: mount_stake(conn, register(suffix, [@wallet]))

  defp mount_stake(conn, account) do
    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/stake")

    view
  end

  defp activate(view, wallet) do
    render_async(view)
    render_hook(view, "staking_active_wallet", %{"address" => wallet})
    render_async(view)
    view
  end
end
