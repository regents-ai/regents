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

    assert has_element?(view, ".product-proof", "Hosted Repo2RLEnv.")
    refute has_element?(view, ".product-proof a[href*='repo2rlenv']")

    for promise <- ["Buy and sell", "sell it", "leaderboards", "priced through x402"] do
      refute html =~ promise
    end
  end
end
