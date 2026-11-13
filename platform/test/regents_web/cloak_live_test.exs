defmodule RegentsWeb.CloakLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.Cloak

  test "CLOAK_PAGE: the download stays off with its reason", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cloak")

    assert has_element?(
             view,
             "#cloak-page button[disabled][aria-describedby=cloak-download-soon]"
           )

    assert has_element?(view, "#cloak-download-soon")

    assert view |> element(".product-proof [data-proof-status]") |> has_element?()
    refute has_element?(view, ".product-proof [data-proof-status=live]")
  end

  test "CLOAK_CARDS: Cloak's four cards stand on their stills and each opens the page's Protections",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/cloak")
    cards = html |> Floki.parse_document!() |> Floki.find("#product-cards > li")

    assert length(cards) == length(Cloak.cards())
    assert has_element?(view, "#protections")

    for card <- cards do
      assert Floki.attribute(card, "a.value-card__face", "href") == ["/cloak#protections"]
      assert Floki.attribute(card, "a.value-card__face", "target") == []

      [still] = Floki.attribute(card, ".value-card__still", "src")
      assert File.exists?(Path.join(Application.app_dir(:regents, "priv/static"), still))
    end

    view |> element("#product-cards-circuit a.value-card__face") |> render_click()
    assert_patch(view, "/cloak")
    assert has_element?(view, "#protections")
  end
end
