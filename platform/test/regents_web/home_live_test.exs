defmodule RegentsWeb.HomeLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.HomeLive

  # Invariants covered:
  # - smoke: 200 mount and the public-home landmark, outside the signed-in shell
  # - launch-gate: in-app links stay on /app, /stake, /cloak, the public agent guide, the
  #   agent start page, or in-page anchors the document owns

  test "SMOKE: the homepage mounts and keeps its landmark", %{conn: conn} do
    assert conn |> get("/") |> html_response(200)
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#public-home")
    refute has_element?(view, "#app-shell")
  end

  # The Overview, Stake and Cloak are the product pages the homepage sends visitors
  # to; every other internal link is a public page that stays open while the gate is
  # closed.
  @open_paths ~w(/app /stake /cloak /start /agents.md /llms.txt /docs /about)

  test "the public homepage never links into a route the launch gate holds", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    anchors = attribute(html, "[id]", "id")

    # The staking world opens in a new tab, so its link carries the site's own address.
    for href <- attribute(html, "a", "href"),
        href = String.replace_prefix(href, RegentsWeb.Endpoint.url(), ""),
        href != "/",
        not String.starts_with?(href, "https://") do
      assert href in @open_paths or String.starts_with?(href, "#")
      if String.starts_with?(href, "#"), do: assert(String.trim_leading(href, "#") in anchors)
    end
  end

  test "NAV_MEANINGS: product tabs open their sites; Protocol staking; Enter App the app", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    # Founder decision (2026-09-28): the tab is named Protocol, and it opens Stake.
    assert html =~ ~r/id="home-nav-protocol".*?<span class="rg-button__label">\s*Protocol\s*</s
    assert attribute(html, "#home-nav-protocol", "href") == ["/stake"]
    # Founder decision (2026-11-12): Enter App opens the app's Overview.
    assert attribute(html, "#home-content a.rl-hero-cta", "href") == ["/app"]

    assert attribute(html, "#home-glass nav.home__foot a", "href") ==
             ~w(https://patchbay.help https://autolaunch.sh https://techtree.sh https://keyfleet.ai /stake /cloak)
  end

  test "PLANNED_HAS_NO_LINK: a planned feature is never offered as something to try" do
    planned =
      for product <- HomeLive.products(),
          proof <- product.proofs,
          proof.status == :planned,
          do: proof

    assert Enum.map(planned, & &1.title) == ["NVIDIA NeMo harnesses."]

    assert Enum.all?(planned, &is_nil(&1.link))
  end

  test "the page and the agent guide read in the same order", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    order =
      ["Regents Labs", "We build tools for people and their agents.", "Enter App"] ++
        ["Agent prompt", HomeLive.agent_prompt(), "Agent Tools"] ++
        ["Products"] ++ ~w(Patchbay Autolaunch Techtree Keyfleet Protocol Cloak)

    assert in_order?(text(html, "#home-glass"), order)
    assert in_order?(HomeLive.agent_markdown(), order ++ ["© 2026 Regents Labs"])

    assert Regex.scan(~r/^## (.+)$/m, HomeLive.agent_markdown(), capture: :all_but_first) ==
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#home-glass h2")
             |> Enum.map(&[&1 |> LazyHTML.text() |> String.trim()])
  end

  test "the panel shows the agent prompt, which sends the agent to this site's pages", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    assert text(html, "#home-prompt-text") == HomeLive.agent_prompt()

    for path <- ~w(/llms.txt / /start),
        do: assert(HomeLive.agent_prompt() =~ RegentsWeb.PublicDocuments.url(path))
  end

  test "the panel's foot is the products alone, and the copyright stands outside it", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "#home-glass .home__foot", "aria-labelledby") == [
             "home-products-title"
           ]

    assert text(html, "#home-products-title") == "Products"

    assert attribute(html, "#home-glass .home__foot a", "id") ==
             Enum.map(~w(patchbay autolaunch techtree keyfleet protocol cloak), &"home-nav-#{&1}")

    assert text(html, "#public-home > .home__copyright") == "© 2026 Regents Labs"
  end

  test "the lab's name stands once, then says one plain line", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    line = "We build tools for people and their agents. REGENT stakers share in the revenue."

    assert text(html, "h1") == "Regents Labs"
    assert text(html, "#home-content .rl-statement__line") == line
    assert HomeLive.agent_markdown() =~ ~r/\A# Regents Labs\n\n#{Regex.escape(line)}\n/
  end

  test "the picture behind the panel is decoration, hidden from assistive technology", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/")

    assert attribute(html, "#public-home img.home__still", "alt") == [""]
    assert attribute(html, "#public-home img.home__still", "aria-hidden") == ["true"]
    assert attribute(html, "#home-canvas", "aria-hidden") == ["true"]
    assert attribute(html, "[data-product-tiles-canvas]", "aria-hidden") == ["true"]
  end

  # Founder decision (2026-10-30): the home page never sets words in bold inside a sentence.
  test "the home page sets no words in bold", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html
           |> LazyHTML.from_document()
           |> LazyHTML.query("#home-content strong, #home-content b")
           |> Enum.empty?()
  end

  defp text(html, selector),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.text()
      |> String.trim()

  defp in_order?(text, words) do
    Enum.reduce_while(words, 0, fn word, from ->
      case :binary.match(text, word, scope: {from, byte_size(text) - from}) do
        {at, length} -> {:cont, at + length}
        :nomatch -> {:halt, false}
      end
    end)
    |> is_integer()
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
