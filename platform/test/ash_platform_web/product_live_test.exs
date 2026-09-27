defmodule AshPlatformWeb.ProductLiveTest do
  use AshPlatformWeb.ConnCase, async: true

  alias AshPlatformWeb.HomeLive

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
    assert has_element?(view, ".product-proof", "Hosted Repo2RLEnv.")
    refute has_element?(view, ".product-proof a[href*='repo2rlenv']")

    for promise <- ["Buy and sell", "sell it", "leaderboards", "priced through x402"] do
      refute html =~ promise
    end
  end

  test "PRODUCT_API: each card in the product data has exactly the published fields", %{
    conn: conn
  } do
    schema =
      get(conn, "/openapi.json")
      |> json_response(200)
      |> get_in(["components", "schemas", "Product", "properties", "what_it_does", "items"])

    for slug <- ~w(techtree patchbay),
        proof <-
          json_response(get(conn, "/api/v1/products/#{slug}"), 200)["product"]["what_it_does"] do
      assert Map.keys(proof) |> Enum.sort() == Enum.sort(schema["required"])
      assert proof["status"] in schema["properties"]["status"]["enum"]
      if proof["status"] == "planned", do: assert(proof["link"] == nil)
    end
  end
end
