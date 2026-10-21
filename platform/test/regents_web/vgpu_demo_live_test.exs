defmodule RegentsWeb.VgpuDemoLiveTest do
  use RegentsWeb.ConnCase, async: true

  # Invariants covered:
  # - smoke: 200 mount and the public-home landmark, outside the signed-in shell
  # - links: in-app links go to the home page, the public agent guide, or in-page
  #   anchors the document owns

  test "SMOKE: the vgpu demo mounts and keeps its landmark", %{conn: conn} do
    assert conn |> get("/vgpu-demo") |> html_response(200)
    {:ok, view, _html} = live(conn, "/vgpu-demo")
    assert has_element?(view, "#public-home")
    refute has_element?(view, "#app-shell")
  end

  # The home page is the one product page the demo sends visitors to; every other
  # internal link is a public page that stays open while the gate is closed.
  @open_paths ~w(/agents.md /llms.txt /docs /about /contact /privacy /terms)

  test "the vgpu demo links only to the home page and pages that stay open", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/vgpu-demo")

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

  test "NAV_MEANINGS: product tabs open their sites; Protocol and App open the home page", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, "/vgpu-demo")

    assert html =~ ~r/id="home-nav-protocol".*?<span class="rg-button__label">\s*Protocol\s*</s
    assert attribute(html, "#home-nav-protocol", "href") == ["/"]
    assert attribute(html, ".rl-header-links a.rl-action", "href") == ["/"]

    assert attribute(html, ".rl-product-tabs a", "href") ==
             ~w(https://autolaunch.sh https://techtree.sh https://patchbay.help https://keyfleet.ai /)
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end
