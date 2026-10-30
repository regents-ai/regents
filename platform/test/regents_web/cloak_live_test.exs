defmodule RegentsWeb.CloakLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.Cloak

  test "CLOAK_PAGE: the download stays off with its reason, and the guide is one press away",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cloak")

    assert has_element?(
             view,
             "#cloak-page button[disabled][aria-describedby=cloak-download-soon]"
           )

    assert has_element?(view, "#cloak-download-soon")
    assert has_element?(view, "#cloak-page a[href='/cloak/guide']")

    assert view |> element(".product-proof [data-proof-status]") |> has_element?()
    refute has_element?(view, ".product-proof [data-proof-status=live]")
  end

  test "CLOAK_GUIDE: people and agents read the same guide", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cloak/guide")
    assert has_element?(view, "#cloak-guide h1")

    markdown =
      build_conn()
      |> put_req_header("accept", "text/markdown")
      |> get("/cloak/guide")
      |> response(200)

    assert markdown == Cloak.guide_markdown()
  end
end
