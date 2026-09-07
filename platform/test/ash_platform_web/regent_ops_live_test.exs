defmodule AshPlatformWeb.RegentOpsLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Accounts
  alias AshPlatform.Actors.System
  alias AshPlatform.Staking.SnapshotCache

  @wallet "0x1111111111111111111111111111111111111111"
  @refresh_failure "Refresh failed. The last confirmed Base snapshot remains on screen."

  test "anonymous visitors meet a product Overview that promises no wallet", %{conn: conn} do
    seed_shared_reading()
    {:ok, view, html} = live(conn, "/app")

    assert has_element?(view, "#regent-ops-overview .regent-ops-heading h1")

    products = ~s(ul[aria-label="Products"])
    assert has_element?(view, "#{products} h2", "Regents")
    assert has_element?(view, "#{products} h2", "Autolaunch")
    assert has_element?(view, "#{products} h2", "Techtree")
    assert has_element?(view, "#{products} h2", "Patchbay")
    assert has_element?(view, ~s(#{products} a[href="/stake"]), "Stake")
    assert has_element?(view, ~s(#{products} a[href="/redeem"]), "Redeem")

    for site <- ["https://autolaunch.sh", "https://techtree.sh", "https://patchbay.help"] do
      assert has_element?(view, ~s(#{products} a[href="#{site}"][rel="noopener noreferrer"]))
    end

    assert has_element?(view, "details.regent-ops-fit summary", "How the products fit together")

    # Account details are a closed secondary disclosure for a visitor.
    assert has_element?(view, "details#regent-ops-account")
    refute has_element?(view, "details#regent-ops-account[open]")
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
  test "the account summary is a definition list", %{conn: conn} do
    seed_shared_reading()
    {:ok, view, _html} = live(conn, "/app")

    assert has_element?(
             view,
             ~s(dl.regent-ops-summary[aria-label="Account summary"] > div > dt)
           )

    assert has_element?(view, ~s(dl.regent-ops-summary > div > dd))
  end

  # The product map is public copy, so a pending or failed Base read never
  # withdraws it or the account actions, and the unavailable notice keeps its word.
  test "products and account actions outlive the network summary read", %{conn: conn} do
    SnapshotCache.clear()
    on_exit(&SnapshotCache.clear/0)

    {:ok, view, html} = live(conn, "/app")

    assert has_element?(view, ~s(ul[aria-label="Products"] h2), "Techtree")
    assert html =~ "Network details are unavailable right now."
    refute has_element?(view, "dl.regent-ops-summary")

    actions = ~s(nav[aria-label="Account actions"])
    assert has_element?(view, ~s(#{actions} a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(#{actions} a[href="/redeem"]), "Redeem Animata")
    assert has_element?(view, ~s(#{actions} a[href="/formation"]), "Run your Regent")
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
  end

  test "a signed-in account sees its wallet balances, position, and rewards open", %{
    conn: conn
  } do
    seed_shared_reading()

    {:ok, account} =
      Accounts.register_verified("did:privy:regent-ops", @wallet, [@wallet], actor: %System{})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    html = render_async(view)

    assert has_element?(view, "details#regent-ops-account[open]")
    assert html =~ "0x1111…1111"
    assert html =~ "10 REGENT"
    assert html =~ "4.25 USDC"
    assert html =~ "5 REGENT"
    assert html =~ "1.50 USDC"
    assert html =~ "2 REGENT"
    assert has_element?(view, ~s(a[href="/formation"]), "Run your Regent")
    refute html =~ "Sign in to see any wallet verified on your account"
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
  end

  # A wallet reading that fails says nothing about the wallet, so its figures are
  # left blank. Printing blanks and nothing else would tell the account holder
  # their balances are zero, so the page says the reading failed and keeps the
  # contract figures every visitor shares.
  test "a failed wallet reading is named, not shown as blanks", %{conn: conn} do
    seed_shared_reading()
    Application.put_env(:ash_platform, :test_staking_wallet_error, :provider_failure)
    on_exit(fn -> Application.delete_env(:ash_platform, :test_staking_wallet_error) end)

    {:ok, account} =
      Accounts.register_verified("did:privy:regent-ops-failure", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, _html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    html = render_async(view)

    assert has_element?(view, ~s(.regent-ops-status[role="alert"]), @refresh_failure)
    assert html =~ "100 REGENT"
    assert has_element?(view, "dl.regent-ops-summary")
    refute html =~ "Network details are unavailable right now."
  end

  # The shared contract reading already exists before anyone opens the page,
  # exactly as it does on a running server after its own first read.
  defp seed_shared_reading do
    SnapshotCache.clear()
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    on_exit(&SnapshotCache.clear/0)
    assert :ok = SnapshotCache.refresh(self())
    assert_receive {:staking_snapshot, _reading}
  end
end
