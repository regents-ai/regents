defmodule AshPlatformWeb.StakeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  setup do
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

  test "PUBLIC_FACTS: anonymous visitors see current Base facts and no wallet controls", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/stake")
    html = render_async(view)
    assert html =~ "Stake $REGENT. Receive revenue tokens equal to your staked percentage."
    assert html =~ "Total staked"
    assert html =~ "100 REGENT"
    assert html =~ "Connect your account"
    refute has_element?(view, "[phx-click=prepare_staking]")
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
    assert render(view) =~ "Wallet stake"
    assert render(view) =~ "5 REGENT"
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
