defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  @products [
    {"formation", "formation", "/formation", "Formation"},
    {"autolaunch", "autolaunch", "/autolaunch", "Autolaunch"},
    {"techtree", "techtree", "/techtree", "Techtree"},
    {"regents-labs", "regent", "/app", "Regents Labs"}
  ]

  test "the header indexes four marketing chapters while product gateways enter apps", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#public-home[phx-hook=HomeHero]")
    assert has_element?(view, "[data-home-header]")
    assert has_element?(view, "[data-home-hero-copy]")
    assert has_element?(view, "[data-home-hero-cards]")

    for {anchor, card_key, app_path, label} <- @products do
      assert has_element?(
               view,
               "#home-product-tab-#{anchor}[href=\"##{anchor}\"]",
               label
             )

      assert has_element?(
               view,
               "#home-card-#{card_key}[data-home-hero-card][href=\"#{app_path}\"]",
               label
             )

      assert has_element?(view, "##{anchor}.rl-chapter")
    end

    assert length(Regex.scan(~r/data-home-hero-card=""/, html)) == 4
    assert length(Regex.scan(~r/class="rl-open-label"/, html)) == 4

    assert length(
             Regex.scan(~r/<section id="(?:formation|autolaunch|techtree|regents-labs)"/, html)
           ) == 4

    assert has_element?(view, ~s(.rl-header-actions a[href="/app"]), "Sign In")
    assert has_element?(view, ~s(.rl-header-actions a[href="/formation"]), "Run your Regent")
  end

  test "every header control names a real destination", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(.rl-brand[href="/"]), "Regents Labs")

    assert attribute(html, ".rl-header a", "href") == [
             "/",
             "#formation",
             "#autolaunch",
             "#techtree",
             "#regents-labs",
             "/app",
             "/formation"
           ]
  end

  test "the hero promises a hosted Regent and says where its second action goes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             ".rl-hero-copy p",
             "Run your Regent in the cloud, publish what it knows, bring it to market"
           )

    assert has_element?(view, ~s(.rl-hero-actions a[href="#techtree"]), "How Techtree works")
  end

  test "the page closes on Techtree with Autolaunch beside it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(section#home-closing[aria-labelledby="home-closing-title"] h2#home-closing-title),
             "Start with the public record."
           )

    assert has_element?(
             view,
             "#home-closing p",
             "Techtree is open to read without an account. Autolaunch is where the work becomes a market."
           )

    assert has_element?(
             view,
             ~s(#home-closing a.rl-action--strong[href="/techtree"]),
             "Explore Techtree"
           )

    assert has_element?(
             view,
             "#home-closing a.rl-action:not(.rl-action--strong)[href=\"/autolaunch\"]",
             "Open Autolaunch"
           )

    assert attribute(html, "main > section[id]", "id") ==
             Enum.map(@products, &elem(&1, 0)) ++ ["home-closing"]
  end

  test "the footer offers the brand, the four chapters, and a copyright line", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ".rl-footer .rl-footer-brand strong", "Regents Labs")
    assert has_element?(view, ".rl-footer p", "© 2026 Regents Labs")

    for {anchor, _card_key, _app_path, label} <- @products do
      assert has_element?(view, ~s(.rl-footer nav a[href="##{anchor}"]), label)
    end

    assert attribute(html, ".rl-footer a", "href") ==
             Enum.map(@products, &"##{elem(&1, 0)}")
  end

  test "the hero bento leads with Techtree and places Autolaunch second", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "[data-home-hero-card]", "id") ==
             ~w(home-card-techtree home-card-autolaunch home-card-formation home-card-regent)
  end

  test "Formation copy claims only the Nous Portal route to a cloud runtime", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#home-card-formation", "Run your Regent in Nous Portal.")
    assert html =~ "Nous Portal is where you create and manage your Regent’s cloud runtime."
    assert has_element?(view, "#formation .rl-proof-grid article", "Open Nous Portal")
    assert has_element?(view, "#formation .rl-proof-grid article", "Your session stays open")

    for provisioning_claim <- ["One active Regent", "Provision", "private cloud"] do
      refute html =~ provisioning_claim
    end
  end

  test "each marketing chapter has a labelled heading and its app action", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for {anchor, _card_key, app_path, _label} <- @products do
      assert has_element?(
               view,
               "section##{anchor}[aria-labelledby=\"#{anchor}-title\"] h2##{anchor}-title"
             )

      assert has_element?(view, "section##{anchor} a[href=\"#{app_path}\"]")
    end

    assert html =~ "Formation / Live"
    assert html =~ "Autolaunch / Preview"
    assert html =~ "Techtree / Preview"
    assert html =~ "Regents Labs / Live"
  end

  test "the hero preserves the approved art and readable server content", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1#home-title", "Build agents that can own their work.")

    assert has_element?(
             view,
             ~s(img.rl-hero-art[src="/images/home/hero-bg-dark.svg"][loading="eager"])
           )

    assert html =~ "Open infrastructure for sovereign agents"

    assert has_element?(
             view,
             ~s(.rl-hero-actions a.rl-action--strong[href="/formation"]),
             "Run your Regent"
           )

    assert html =~ "Build public signal before launch."
    assert html =~ "Make knowledge inspectable."
    assert html =~ "Keep identity and value actions together."
    assert html =~ "X, GitHub, Farcaster, ENS, and World"
    assert html =~ "Map and List"
    assert html =~ "Focused discussion"
    assert html =~ "Local Marimo"
    assert html =~ "Marimo WASM notebooks"
    assert html =~ "Agent participation"
    assert html =~ "publish evidence through Regents CLI"
    assert html =~ "node creation stays read-only here"
    assert length(Regex.scan(~r/data-home-voxel=""/, html)) == 24

    refute html =~ "Prime Intellect"
    refute html =~ "partners"
    refute html =~ "customers"
    refute html =~ ~s(href="/app/profile")
  end

  test "the homepage stays outside the application shell and within its HTML budget", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ ~s(id="app-shell")
    assert byte_size(html) <= 60 * 1024
  end

  test "the primary header action keeps contrast on hover" do
    css = File.read!(Path.expand("../../assets/css/pages/home.css", __DIR__))

    assert css =~ ".rl-header-entry--strong:hover"
    assert css =~ "background: var(--rl-ink)"
    assert css =~ "color: var(--rl-bg)"
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
