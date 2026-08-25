defmodule AshPlatformWeb.RegentOpsLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"

  test "U1_U2_U3_VALID_ACCOUNT_ENTRY: anonymous visitors meet an Account page that promises no wallet",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")
    html = render_async(view)

    assert has_element?(view, "#regent-ops-overview .regent-ops-heading h1", "Account")
    assert html =~ "See your account, any verified wallet, balances, and rewards on Base."
    assert html =~ "Regents Labs · Base"
    assert html =~ "100 REGENT"

    assert html =~
             "Sign in to see any wallet verified on your account and the balances available to it."

    assert has_element?(view, ~s(a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(a[href="/redeem"]), "Redeem Animata")
    assert has_element?(view, ~s(a[href="/formation"]), "Run your Regent")
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
    refute html =~ "/hermes"
    refute html =~ "0x1111…1111"
  end

  # Each metric is a term and its value inside a definition list, so the pairing
  # is exposed as a pairing rather than as loose terms in a generic container.
  test "U2_VALID_METRIC_SEMANTICS: the overview summary is a definition list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/app")
    render_async(view)

    assert has_element?(
             view,
             ~s(dl.regent-ops-summary[aria-label="Account summary"] > div > dt)
           )

    assert has_element?(view, ~s(dl.regent-ops-summary > div > dd))
  end

  # Stake, Redeem, and Run your Regent are things an account can do, not readings
  # of the network summary, so a pending or failed Base read never withdraws them
  # and the unavailable notice keeps its word.
  test "U6_VALID_ACTIONS_WITHOUT_NETWORK_SUMMARY: account actions outlive the summary read", %{
    conn: conn
  } do
    Application.put_env(:ash_platform, :test_staking_overview_error, :chain_unavailable)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_overview_error) end)

    {:ok, view, loading} = live(conn, "/app")

    assert loading =~ "Loading network details…"
    assert loading =~ "Stake REGENT"
    assert loading =~ "Redeem Animata"
    assert loading =~ "Run your Regent"

    html = render_async(view)

    assert html =~ "Network details are unavailable right now."
    refute has_element?(view, "dl.regent-ops-summary")

    actions = ~s(nav[aria-label="Account actions"])
    assert has_element?(view, ~s(#{actions} a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(#{actions} a[href="/redeem"]), "Redeem Animata")
    assert has_element?(view, ~s(#{actions} a[href="/formation"]), "Run your Regent")
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
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
    assert has_element?(view, ~s(a[href="/formation"]), "Run your Regent")
    refute html =~ "Sign in to see any wallet verified on your account"
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
  end
end
