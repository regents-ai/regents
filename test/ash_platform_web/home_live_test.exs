defmodule AshPlatformWeb.HomeLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  @products [
    {"formation", "formation", "Formation"},
    {"autolaunch", "autolaunch", "Autolaunch"},
    {"techtree", "techtree", "Techtree"},
    {"regents-labs", "regent", "Regents Labs"}
  ]

  @nav [
    {"techtree", "Techtree", "#techtree"},
    {"autolaunch", "Autolaunch", "#autolaunch"},
    {"regent", "Regent", "#regents-labs"},
    {"about", "About", "#home-closing"}
  ]

  test "the header indexes the page and the bento reaches every chapter", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "#public-home[phx-hook=HomeHero]")
    assert has_element?(view, "[data-home-header]")
    assert has_element?(view, "[data-home-hero-copy]")
    assert has_element?(view, "#home-products[data-home-hero-cards]")

    for {slug, label, target} <- @nav do
      assert has_element?(view, "#home-nav-#{slug}[href=\"#{target}\"]", label)
    end

    for {anchor, card_key, label} <- @products do
      assert has_element?(
               view,
               "#home-card-#{card_key}[data-home-hero-card][href=\"##{anchor}\"]",
               label
             )

      assert has_element?(view, "##{anchor}.rl-chapter")
    end

    assert length(Regex.scan(~r/data-home-hero-card=""/, html)) == 4
    assert length(Regex.scan(~r/class="rl-card-label"/, html)) == 4

    assert length(
             Regex.scan(~r/<section id="(?:formation|autolaunch|techtree|regents-labs)"/, html)
           ) == 4
  end

  test "the public homepage never links into a route the launch gate holds", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    anchors = attribute(html, "[id]", "id")

    for href <- attribute(html, "a", "href"), href != "/" do
      assert String.starts_with?(href, "#")
      assert String.trim_leading(href, "#") in anchors
    end

    for held <- ~w(/app /formation /techtree /autolaunch /regents) do
      refute html =~ ~s(href="#{held})
    end
  end

  test "every header control names a real destination", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, ~s(.rl-brand[href="/"]), "Regents Labs")
    assert has_element?(view, ".rl-header-note", "Proof, capital, and operations for agents.")

    assert attribute(html, ".rl-header a", "href") ==
             ["/" | Enum.map(@nav, &elem(&1, 2))]
  end

  test "the hero states the stack and offers one in-page way into it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(view, "h1#home-title", "Prove the edge. Fund the agent. Keep it running.")
    assert html =~ "The economic stack for agents"

    assert has_element?(
             view,
             ".rl-hero-copy p",
             "Techtree makes the work checkable. Autolaunch turns proven edge into funding and a visible revenue path. Regent keeps the same agent operating under one identity."
           )

    assert attribute(html, ".rl-hero-actions a", "href") == ["#techtree"]

    assert has_element?(
             view,
             ~s(.rl-hero-actions a.rl-action--strong[href="#techtree"]),
             "See how it works"
           )
  end

  test "the page closes on the system summary the About tab points at", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(section#home-closing[aria-labelledby="home-closing-title"] h2#home-closing-title),
             "Build the proof. Earn the trust. Launch when the work is ready."
           )

    assert has_element?(
             view,
             "#home-closing p",
             "Regents connects one agent identity across public work, capital formation, and continued operation."
           )

    assert attribute(html, "#home-closing a", "href") == ["#home-products"]

    assert has_element?(
             view,
             ~s(#home-closing a.rl-action--strong[href="#home-products"]),
             "Explore the system"
           )

    assert attribute(html, "main > section[id]", "id") ==
             Enum.map(@products, &elem(&1, 0)) ++ ["home-closing"]
  end

  test "the footer carries the two company lines, a copyright, and no links", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ".rl-footer .rl-footer-brand strong",
             "Regents Labs builds Techtree and Autolaunch."
           )

    assert has_element?(
             view,
             ".rl-footer .rl-footer-brand span",
             "Agent proof. Agent capital. Onchain revenue."
           )

    assert has_element?(view, ".rl-footer p", "© 2026 Regents Labs")
    assert attribute(html, ".rl-footer a", "href") == []
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

  test "each marketing chapter has a labelled heading and reads without an action", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for {anchor, _card_key, _label} <- @products do
      assert has_element?(
               view,
               "section##{anchor}[aria-labelledby=\"#{anchor}-title\"] h2##{anchor}-title"
             )

      refute has_element?(view, "section##{anchor} a")
    end

    assert html =~ "Formation / Live"
    assert html =~ "Autolaunch / Preview"
    assert html =~ "Techtree / Preview"
    assert html =~ "Regents Labs / Live"

    for proof <- [
          "Map and List",
          "Evidence you can check",
          "Notebooks on your device",
          "Signed-in discussion",
          "Agent participation"
        ] do
      assert has_element?(view, "#techtree .rl-proof-grid article", proof)
    end

    assert html =~ "publish evidence through Regents CLI"
    assert html =~ "node creation stays read-only here"
  end

  test "the hero preserves the approved art and readable server content", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(img.rl-hero-art[src="/images/home/hero-bg-dark.svg"][loading="eager"])
           )

    assert html =~ "Build public signal before launch."
    assert html =~ "Turn agent runs into public, checkable proof."
    assert html =~ "Keep identity and value actions together."
    assert html =~ "X, GitHub, Farcaster, ENS, and World"
    assert length(Regex.scan(~r/data-home-voxel=""/, html)) == 24

    refute html =~ "Prime Intellect"
    refute html =~ "partners"
    refute html =~ "customers"
  end

  test "the page offers only the two actions the copy promises", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    actions =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("a.rl-action")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert actions == ["See how it works", "Explore the system"]

    for held_action <- ["Sign In", "Read the litepaper"] do
      refute html =~ held_action
    end
  end

  test "the homepage stays outside the application shell and within its HTML budget", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    refute html =~ ~s(id="app-shell")
    assert byte_size(html) <= 60 * 1024
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
