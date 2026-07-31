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

    refute html =~ ~s(id="home-card-formation" href="#formation")
    refute html =~ ~s(id="home-card-autolaunch" href="#autolaunch")
    refute html =~ ~s(id="home-card-techtree" href="#techtree")
    refute html =~ ~s(id="home-card-regent" href="#regents-labs")
    assert has_element?(view, ~s(.rl-header-actions a[href="/app"]), "Sign In")
    assert has_element?(view, ~s(.rl-header-actions a[href="/formation"]), "Form a Regent")
  end

  test "each marketing chapter has an ordered, labelled heading and its app action", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    for {anchor, _card_key, app_path, _label} <- @products do
      assert has_element?(
               view,
               "section##{anchor}[aria-labelledby=\"#{anchor}-title\"] h2##{anchor}-title"
             )

      assert has_element?(view, "section##{anchor} a[href=\"#{app_path}\"]")
    end

    chapter_positions =
      Enum.map(@products, fn {anchor, _, _, _} ->
        {position, _} = :binary.match(html, ~s(<section id="#{anchor}"))
        position
      end)

    assert chapter_positions == Enum.sort(chapter_positions)
    assert html =~ "Formation / Preview"
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
    assert html =~ "Form a Regent"
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
end
