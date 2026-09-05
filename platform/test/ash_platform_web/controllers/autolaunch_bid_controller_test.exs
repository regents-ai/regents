defmodule AshPlatformWeb.AutolaunchBidControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.BidFixture

  @removed [
    "/api/autolaunch/v1/auctions/:id/bids",
    "/api/autolaunch/v1/bids/:id/exit",
    "/api/autolaunch/v1/bids/:id/return",
    "/api/autolaunch/v1/bids/:id/claim"
  ]

  test "THE_OBSOLETE_ACTION_PATH_IS_GONE: no route can prepare a bid or a bid position" do
    paths = Enum.map(AshPlatformWeb.Router.__routes__(), & &1.path)

    for path <- @removed, do: refute(path in paths)
    assert "/api/autolaunch/v1/auctions/:id/bid-quote" in paths

    refute Enum.any?(paths, &String.contains?(&1, "submit"))
    refute Enum.any?(paths, &String.contains?(&1, "broadcast"))
  end

  test "THE_OBSOLETE_ACTION_PATH_IS_GONE: the controller exposes only public auction reads" do
    exported =
      AshPlatformWeb.AutolaunchAuctionController.__info__(:functions)
      |> Keyword.keys()
      |> Enum.filter(
        &(&1 in [
            :index,
            :show,
            :bid_quote,
            :prepare_bid,
            :prepare_bid_exit,
            :prepare_bid_return,
            :prepare_bid_claim
          ])
      )
      |> Enum.sort()

    assert exported == [:bid_quote, :index, :show]
  end

  test "PUBLIC_QUOTE_IS_STORED_ONLY: the surviving quote route needs no session and prepares nothing",
       %{conn: conn} do
    auction = auction!("Quote only")
    path = "/api/autolaunch/v1/auctions/#{auction.id}/bid-quote"

    assert %{"data" => quote} =
             conn |> post(path, %{"amount" => "12.5", "max_price" => "3"}) |> json_response(200)

    assert quote["amount"] == "12.5"
    assert quote["estimated_tokens_if_end_now"] == "5"
    refute Map.has_key?(quote, "data")
    refute Map.has_key?(quote, "expected_signer")
  end
end
