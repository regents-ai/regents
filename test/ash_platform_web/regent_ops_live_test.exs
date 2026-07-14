defmodule AshPlatformWeb.RegentOpsLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"

  test "anonymous visitors see the public Regents Labs overview without invented account data", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/app")
    html = render_async(view)

    assert html =~ "Regents Labs"
    assert html =~ "100 REGENT"
    assert html =~ "Sign in to see your wallet"
    assert has_element?(view, ~s(a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(a[href="/redeem"]), "Redeem Animata")
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
    refute html =~ "0x1111…1111"
  end

  test "a signed-in account sees its wallet balances, position, and rewards", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:regent-ops", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    html = render_async(view)

    assert html =~ "0x1111…1111"
    assert html =~ "10 REGENT"
    assert html =~ "4.25 USDC"
    assert html =~ "5 REGENT"
    assert html =~ "1.5 USDC"
    assert html =~ "2 REGENT"
    refute html =~ "Sign in to see your wallet"
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
  end
end
