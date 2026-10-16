defmodule RegentsWeb.HomeLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.HomeLive

  # Invariants covered:
  # - smoke: 200 mount and the public-home landmark, outside the signed-in shell
  # - launch-gate: in-app links stay on /stake, the public agent guide, or in-page
  #   anchors the document owns

  test "SMOKE: the homepage mounts and keeps its landmark", %{conn: conn} do
    assert conn |> get("/") |> html_response(200)
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#public-home")
    refute has_element?(view, "#app-shell")
  end

  # Stake is the one product page the homepage sends visitors to; every other
  # internal link is a public page that stays open while the gate is closed.
  @open_paths ~w(/app /stake /agents.md /llms.txt /docs /about /contact /privacy /terms)

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

  test "NAV_MEANINGS: product tabs open their sites; Protocol and App open staking", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    # Founder decision (2026-09-28): the tab is named Protocol, and it and App open Stake.
    assert html =~ ~r/id="home-nav-protocol"[^>]*>\s*Protocol\s*</
    assert attribute(html, "#home-nav-protocol", "href") == ["/stake"]
    assert attribute(html, ".rl-header-links a.rl-action", "href") == ["/stake"]

    assert attribute(html, ".rl-product-tabs a", "href") ==
             ~w(https://autolaunch.sh https://techtree.sh https://patchbay.help https://keyfleet.ai /stake)
  end

  test "PLANNED_HAS_NO_LINK: a planned feature is never offered as something to try" do
    planned =
      for product <- HomeLive.products(),
          proof <- product.proofs,
          proof.status == :planned,
          do: proof

    assert Enum.map(planned, & &1.title) == [
             "NVIDIA NeMo harnesses.",
             "Personal agents, shared work.",
             "A shared treasury.",
             "No top-down orchestration."
           ]

    assert Enum.all?(planned, &is_nil(&1.link))
  end

  test "the homepage and agent guide claim only what Techtree offers", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    guide = HomeLive.agent_markdown()

    for promise <- ["Buy and sell", "leaderboards", "and earn", "x402 service"] do
      refute html =~ promise
      refute guide =~ promise
    end

    assert guide =~ "(Planned)"
    assert guide =~ "(Experimental: [Explore Techtree](https://techtree.sh/start))"
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
