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

  # Each metric is a term and its value inside a definition list, so the pairing
  # is exposed as a pairing rather than as loose terms in a generic container.
  test "U2_VALID_METRIC_SEMANTICS: the overview summary is a definition list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")
    render_async(view)

    assert has_element?(
             view,
             ~s(dl.regent-ops-summary[aria-label="Regents Labs summary"] > div > dt)
           )

    assert has_element?(view, ~s(dl.regent-ops-summary > div > dd))
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
