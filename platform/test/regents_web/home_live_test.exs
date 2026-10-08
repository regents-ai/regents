defmodule RegentsWeb.HomeLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.HomeLive

  # Invariants covered:
  # - smoke: 200 mount and the public-home landmark, outside the signed-in shell
  # - launch-gate: in-app links stay on /stake, the public agent guide, or in-page
  #   anchors the document owns
  # - proof-status: each card names its status, and only a feature that can be
  #   tried now links to it

  test "SMOKE: the homepage mounts and keeps its landmark", %{conn: conn} do
    assert conn |> get("/") |> html_response(200)
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "#public-home")
    refute has_element?(view, "#app-shell")
  end

  # Stake is the one product page the homepage sends visitors to; every other
  # internal link is a public page that stays open while the gate is closed.
  @open_paths ~w(/app /stake /llms.txt /docs /about /contact /privacy /terms)

  test "the public homepage never links into a route the launch gate holds", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    anchors = attribute(html, "[id]", "id")

    for href <- attribute(html, "a", "href"),
        href != "/",
        not String.starts_with?(href, "https://") do
      assert href in @open_paths or String.starts_with?(href, "#")
      if String.starts_with?(href, "#"), do: assert(String.trim_leading(href, "#") in anchors)
    end
  end

  test "NAV_MEANINGS: Protocol and App both open staking", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    # Founder decision (2026-09-28): the tab is named Protocol, and it and App open Stake.
    assert html =~ ~r/id="home-nav-protocol"[^>]*>\s*Protocol\s*</
    assert attribute(html, "#home-nav-protocol", "href") == ["/stake"]
    assert attribute(html, ".rl-header-links a.rl-action", "href") == ["/stake"]

    assert attribute(html, ".rl-product-tabs a", "href") ==
             ~w(#autolaunch #techtree #patchbay /stake)
  end

  test "NAV_MEANINGS: the blog header sends each tab and App where the homepage does", %{
    conn: conn
  } do
    html = conn |> get("/articles") |> html_response(200)

    assert attribute(html, "#home-nav-protocol", "href") == ["/stake"]
    assert attribute(html, ".rl-header-links a.rl-action", "href") == ["/stake"]

    assert attribute(html, ".rl-product-tabs a", "href") ==
             ~w(/#autolaunch /#techtree /#patchbay /stake)
  end

  test "PROOF_STATUS: every homepage card says what its product offers today", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for product <- HomeLive.products(), {proof, index} <- Enum.with_index(product.proofs) do
      card = "#home-proof-#{product.anchor}-#{index}"
      assert proof.status in [:live, :experimental, :planned]
      assert has_element?(view, "#{card} [data-proof-status=#{proof.status}]")

      if proof.link do
        assert has_element?(view, "#{card} a[href='#{proof.link.href}']", proof.link.label)
      else
        refute has_element?(view, "#{card} .rg-feature__caption a")
      end
    end
  end

  test "PLANNED_HAS_NO_LINK: a planned feature is never offered as something to try" do
    planned =
      for product <- HomeLive.products(),
          proof <- product.proofs,
          proof.status == :planned,
          do: proof

    assert [%{title: "Hosted Repo2RLEnv."}] = planned
    assert Enum.all?(planned, &is_nil(&1.link))
  end

  test "the Techtree section and agent guide claim only what Techtree offers", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    guide = HomeLive.agent_markdown()

    for promise <- ["Buy and sell", "leaderboards", "and earn", "x402 service"] do
      refute html =~ promise
      refute guide =~ promise
    end

    assert guide =~ "(Planned)"
    assert guide =~ "(Experimental: [Test a skill](https://techtree.sh/start#skill))"
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
