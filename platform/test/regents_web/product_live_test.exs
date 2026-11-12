defmodule RegentsWeb.ProductLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.HomeLive

  test "TECHTREE_PAGE: each card says what Techtree offers today, with a link only to what can be tried",
       %{conn: conn} do
    {:ok, view, html} = live(conn, "/techtree")
    proofs = Enum.find(HomeLive.products(), &(&1.anchor == "techtree")).proofs

    for proof <- proofs do
      assert has_element?(view, ".product-proof [data-proof-status=#{proof.status}]")

      if proof.link,
        do: assert(has_element?(view, ".product-proof a[href='#{proof.link.href}']"))
    end

    assert has_element?(view, ".product-shot figcaption", "techtree.sh, 27 September 2026")
    assert has_element?(view, ".product-proof", "NVIDIA NeMo harnesses.")

    for promise <- ["Buy and sell", "sell it", "leaderboards", "priced through x402"] do
      refute html =~ promise
    end
  end

  test "PRODUCT_CARDS: each product page shows its product's six cards, each opening that product's site in a new tab, and its product data carries the same cards",
       %{conn: conn} do
    schema =
      get(conn, "/openapi.json")
      |> json_response(200)
      |> get_in(["components", "schemas", "Product", "properties", "cards", "items"])

    for slug <- RegentsWeb.ProductDirectory.slugs() do
      {:ok, _view, html} = live(conn, "/#{slug}")
      product = json_response(get(conn, "/api/v1/products/#{slug}"), 200)["product"]
      cards = html |> Floki.parse_document!() |> Floki.find("#product-cards > li")

      assert length(cards) == 6, slug
      assert length(product["cards"]) == 6, slug

      for {card, data} <- Enum.zip(cards, product["cards"]) do
        assert Map.keys(data) |> Enum.sort() == Enum.sort(schema["required"])

        assert [href] = Floki.attribute(card, "a.value-card__face", "href")
        assert href == data["href"]
        assert %URI{scheme: "https", host: host} = URI.parse(href)
        assert host == URI.parse(product["site"]).host
        assert Floki.attribute(card, "a.value-card__face", "target") == ["_blank"]
        assert Floki.attribute(card, "a.value-card__face", "rel") == ["noopener noreferrer"]

        assert words(card, ".value-card__name") == data["name"]
        assert words(card, ".value-card__headline") == data["headline"]
        assert words(card, ".value-card__line") == data["line"]
        assert words(card, ".value-card__action") == data["action"] <> ", opens in a new tab"

        [still] = Floki.attribute(card, ".value-card__still", "src")
        assert File.exists?(Path.join(Application.app_dir(:regents, "priv/static"), still))
      end
    end
  end

  defp words(card, selector),
    do: card |> Floki.find(selector) |> Floki.text() |> String.split() |> Enum.join(" ")

  test "PRODUCT_API: each card in the product data has exactly the published fields", %{
    conn: conn
  } do
    schema =
      get(conn, "/openapi.json")
      |> json_response(200)
      |> get_in(["components", "schemas", "Product", "properties", "what_it_does", "items"])

    for slug <- ~w(techtree patchbay keyfleet),
        proof <-
          json_response(get(conn, "/api/v1/products/#{slug}"), 200)["product"]["what_it_does"] do
      assert Map.keys(proof) |> Enum.sort() == Enum.sort(schema["required"])
      assert proof["status"] in schema["properties"]["status"]["enum"]
      if proof["status"] == "planned", do: assert(proof["link"] == nil)
    end
  end

  test "PRODUCT_API: every product answers only the fields the API description declares", %{
    conn: conn
  } do
    schema =
      get(conn, "/openapi.json")
      |> json_response(200)
      |> get_in(["components", "schemas", "Product"])

    declared = Map.keys(schema["properties"])

    for slug <- RegentsWeb.ProductDirectory.slugs() do
      product = json_response(get(conn, "/api/v1/products/#{slug}"), 200)["product"]

      assert Map.keys(product) -- declared == [], slug
      assert schema["required"] -- Map.keys(product) == [], slug
    end
  end
end
