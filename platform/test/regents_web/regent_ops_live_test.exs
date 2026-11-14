defmodule RegentsWeb.RegentOpsLiveTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.Accounts
  alias Regents.Actors.System
  alias Regents.SharedStakingReading

  @wallet "0x1111111111111111111111111111111111111111"
  @refresh_failure "Couldn’t update just now. The figures shown are from the last successful reading."

  test "anonymous visitors meet a product Overview that promises no wallet", %{conn: conn} do
    seed_shared_reading()
    {:ok, view, html} = live(conn, "/app")

    assert has_element?(view, "#regent-ops-overview .regent-ops-heading h1")

    # One card for each product: the four product sites open in a new tab, staking
    # and Cloak stay on this site.
    products = ~s(ul[aria-label="Products"])
    page = Floki.parse_document!(html)
    assert page |> Floki.find("#{products} > li") |> length() == 6

    # Founder decision (2026-11-12): the site's order of its products.
    assert page |> Floki.find("#{products} .value-card__name") |> Enum.map(&Floki.text/1) ==
             ~w(Keyfleet Autolaunch Protocol Patchbay Techtree Cloak)

    for site <- [
          "https://patchbay.help",
          "https://autolaunch.sh",
          "https://techtree.sh",
          "https://keyfleet.ai"
        ] do
      assert has_element?(
               view,
               ~s(#{products} a[href="#{site}"][target="_blank"][rel="noopener noreferrer"])
             )
    end

    assert has_element?(view, ~s'#{products} a[href="/stake"]:not([target])')
    assert has_element?(view, ~s'#{products} a[href="/cloak"]:not([target])')

    # Every card stands on its own still frame until its panel draws.
    for still <- Floki.attribute(page, ".value-card__still", "src") do
      assert File.exists?(Path.join(Application.app_dir(:regents, "priv/static"), still))
    end

    assert has_element?(view, "details.regent-ops-fit summary")

    # Account details are a closed secondary disclosure for a visitor.
    assert has_element?(view, "details#regent-ops-account")
    refute has_element?(view, "details#regent-ops-account[open]")
    assert html =~ "100 REGENT"

    assert html =~
             "Sign in to see any wallet verified on your account and the balances available to it."

    assert has_element?(view, ~s(a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(a[href="/redeem"]), "Redeem Animata")
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
    refute html =~ ~s(href="/hermes")
    refute html =~ "0x1111..1111"
  end

  # The hero's map: a block for every product that opens what the product's card
  # opens, Sign-in with Agent beside them, and one named line, reachable from the
  # keyboard and with its sentence ready in the caption, for each way the products'
  # guides say they work together. Cloak works on its own.
  test "the hero map joins the products the way their guides describe", %{conn: conn} do
    seed_shared_reading()
    {:ok, _view, html} = live(conn, "/app")
    page = Floki.parse_document!(html)
    map = Floki.find(page, ~s(#regent-ops-map[role="group"][aria-label="Product map"]))

    blocks = Floki.find(map, "a.lab-blocks__place")
    assert length(blocks) == 7

    for block <- blocks, Floki.attribute(block, "data-node") != ["Sign-in with Agent"] do
      [href] = Floki.attribute(block, "href")
      card = Floki.find(page, ~s(ul[aria-label="Products"] a[href="#{href}"]))
      assert length(card) == 1
      assert Floki.attribute(card, "target") == Floki.attribute(block, "target")
    end

    assert map
           |> Floki.find(~s(a.lab-blocks__place[data-node="Sign-in with Agent"][target="_blank"]))
           |> length() == 1

    lines =
      for line <- Floki.find(map, "g.lab-blocks__link") do
        [from] = Floki.attribute(line, "data-from")
        [to] = Floki.attribute(line, "data-to")
        [index] = Floki.attribute(line, "data-link")
        [name] = Floki.attribute(line, "aria-label")
        assert Floki.attribute(line, "tabindex") == ["0"]
        assert Floki.attribute(line, "role") == ["img"]

        # The caption holds the same sentence the line is named with.
        sentence = String.replace_prefix(name, "#{from} and #{to}: ", "")
        assert sentence != name
        said = Floki.find(map, ~s(.lab-blocks__say[data-say="#{index}"]))
        assert Floki.text(said) =~ sentence

        MapSet.new([from, to])
      end

    assert length(lines) == 13

    assert MapSet.new(lines) ==
             MapSet.new(
               Enum.map(
                 [
                   ~w(Techtree Patchbay),
                   ~w(Techtree Protocol),
                   ~w(Patchbay Protocol),
                   ~w(Autolaunch Protocol),
                   ~w(Keyfleet Protocol),
                   ~w(Keyfleet Autolaunch),
                   ~w(Keyfleet Patchbay),
                   ~w(Autolaunch Patchbay)
                 ] ++
                   for(
                     product <- ~w(Patchbay Techtree Autolaunch Keyfleet Protocol),
                     do: ["Sign-in with Agent", product]
                   ),
                 &MapSet.new/1
               )
             )
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
    {:ok, view, html} = live(conn, "/app")

    assert has_element?(view, ~s(ul[aria-label="Products"] a[href="https://techtree.sh"]))
    assert html =~ "Network details are unavailable right now."
    refute has_element?(view, "dl.regent-ops-summary")

    actions = ~s(nav[aria-label="Account actions"])
    assert has_element?(view, ~s(#{actions} a[href="/stake"]), "Stake REGENT")
    assert has_element?(view, ~s(#{actions} a[href="/redeem"]), "Redeem Animata")
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
    assert html =~ "0x1111..1111"
    assert html =~ "10 REGENT"
    assert html =~ "4.25 USDC"
    assert html =~ "5 REGENT"
    assert html =~ "1.50 USDC"
    assert html =~ "2 REGENT"
    refute html =~ "Sign in to see any wallet verified on your account"
    refute has_element?(view, ~s(a[href="/regents/viewer"]))
  end

  # A wallet reading that fails says nothing about the wallet, so its figures are
  # left blank. Printing blanks and nothing else would tell the account holder
  # their balances are zero, so the page says the reading failed and keeps the
  # contract figures every visitor shares.
  test "a failed wallet reading is named, not shown as blanks", %{conn: conn} do
    seed_shared_reading()
    Application.put_env(:regents, :test_staking_wallet_error, :provider_failure)
    on_exit(fn -> Application.delete_env(:regents, :test_staking_wallet_error) end)

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

    # The failure is the answer: nothing is left pulsing as if still on its way.
    refute has_element?(view, "#overview-wallet-skeleton")

    assert has_element?(
             view,
             "dl.regent-ops-balances .figure-unavailable",
             "Unavailable right now"
           )
  end

  # The contract reading failed on arrival and came back later. The account's
  # wallet was never read while there was nothing to show it beside, so it is
  # read the moment the contract figures return, rather than left waiting.
  test "a contract reading that recovers brings the account's wallet with it", %{conn: conn} do
    {:ok, account} =
      Accounts.register_verified("did:privy:regent-ops-recover", @wallet, [@wallet],
        actor: %System{}
      )

    {:ok, view, html} =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> live("/app")

    assert html =~ "Network details are unavailable right now."
    refute has_element?(view, "#overview-network-skeleton")

    SharedStakingReading.share()
    html = render_async(view)

    refute html =~ "Network details are unavailable right now."
    refute has_element?(view, "#overview-wallet-skeleton")
    assert has_element?(view, "dl.regent-ops-balances", "10 REGENT")
    assert has_element?(view, "dl.regent-ops-balances", "4.25 USDC")
  end

  # The shared contract reading already exists before anyone opens the page,
  # exactly as it does on a running server after its own first read.
  defp seed_shared_reading, do: SharedStakingReading.share()
end
