defmodule AshPlatformWeb.AutolaunchBidControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Autolaunch}
  alias AshPlatform.Actors.System

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @auction_address "0x3333333333333333333333333333333333333333"
  @quote_token "0x4444444444444444444444444444444444444444"

  setup do
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)
    on_exit(fn -> restore(:wallet_action_clock, previous_clock) end)

    account =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-controller",
        @wallet,
        [@wallet],
        actor: %System{}
      )

    other =
      Accounts.register_verified!(
        "did:privy:autolaunch-bid-controller-other",
        @other,
        [@other],
        actor: %System{}
      )

    auction =
      Autolaunch.import_auction!(
        "API bid preparation",
        nil,
        false,
        :active,
        ~U[2026-07-31 11:00:00Z],
        actor: %System{}
      )

    auction =
      Autolaunch.set_auction_bid_terms!(
        auction,
        @auction_address,
        @quote_token,
        "QUOTE",
        6,
        "2.5",
        actor: %System{}
      )

    %{account: account, other: other, auction: auction}
  end

  test "public quote is contract-shaped and preparation requires a current session", %{
    conn: conn,
    account: account,
    auction: auction
  } do
    quote_path = "/api/autolaunch/v1/auctions/#{auction.id}/bid-quote"
    prepare_path = "/api/autolaunch/v1/auctions/#{auction.id}/bids"
    params = %{"amount" => "12.5", "max_price" => "3"}

    assert %{"data" => quote} = conn |> post(quote_path, params) |> json_response(200)
    assert quote["amount"] == "12.5"
    assert quote["estimated_tokens_if_end_now"] == "5"

    assert conn |> post(prepare_path, params) |> json_response(401) == %{
             "error" => "unauthorized"
           }

    prepared =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> post(prepare_path, params)
      |> json_response(200)

    assert prepared["data"]["resource"] == "autolaunch_auction"
    assert prepared["data"]["action"] == "submit_bid"
    assert prepared["data"]["expected_signer"] == @wallet
    assert prepared["data"]["approval"]["amount"] == "12500000"
    assert prepared["data"]["approval"]["mode"] == "exact"
  end

  test "post-bid preparation exposes only the stored owner's eligible action", %{
    conn: conn,
    account: account,
    other: other,
    auction: auction
  } do
    bid = bid!(auction, @wallet, "claimable", "9")
    path = "/api/autolaunch/v1/bids/#{bid.bid_id}/claim"

    owned =
      conn
      |> init_test_session(%{human_account_id: account.id})
      |> post(path, %{})
      |> json_response(200)

    assert owned["data"]["action"] == "claim_bid"
    assert owned["data"]["data"] =~ "0x46e04a2f"

    assert conn
           |> init_test_session(%{human_account_id: other.id})
           |> post(path, %{})
           |> json_response(400) == invalid_request()
  end

  test "routes admit preparation but no submission endpoint" do
    routes = AshPlatformWeb.Router.__routes__()
    paths = Enum.map(routes, & &1.path)

    for path <- [
          "/api/autolaunch/v1/auctions/:id/bid-quote",
          "/api/autolaunch/v1/auctions/:id/bids",
          "/api/autolaunch/v1/bids/:id/exit",
          "/api/autolaunch/v1/bids/:id/return",
          "/api/autolaunch/v1/bids/:id/claim"
        ] do
      assert path in paths
    end

    refute Enum.any?(paths, &String.contains?(&1, "submit"))
    refute Enum.any?(paths, &String.contains?(&1, "broadcast"))
  end

  defp bid!(auction, owner, status, onchain_bid_id) do
    bid =
      Autolaunch.import_bid_position!(
        "api-bid-#{status}-#{onchain_bid_id}",
        auction.id,
        owner,
        "1",
        "3",
        "2.5",
        "0.4",
        status,
        nil,
        nil,
        actor: %System{}
      )

    Autolaunch.set_bid_chain_identity!(
      bid,
      @auction_address,
      onchain_bid_id,
      actor: %System{}
    )
  end

  defp invalid_request do
    %{
      "error" => %{
        "code" => "invalid_request",
        "message" => "The query parameters are invalid."
      }
    }
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
