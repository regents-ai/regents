defmodule AshPlatformWeb.AutolaunchAuctionControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch

  defmodule RecordingAutolaunch do
    def list_public_auctions(mode, sort, limit, actor: nil) do
      send(self(), {:list_public_auctions, mode, sort, limit})
      {:ok, []}
    end
  end

  defmodule FailingAutolaunch do
    def list_public_auctions(_mode, _sort, _limit, actor: nil),
      do: {:error, {:sentinel, "private details"}}

    def get_public_auction(_id, actor: nil), do: {:error, {:sentinel, "private details"}}
  end

  test "GET routes expose empty list, detail, and missing envelopes", %{conn: conn} do
    assert conn |> get("/api/autolaunch/v1/auctions") |> json_response(200) == %{"data" => []}

    missing_id = Ash.UUID.generate()

    assert conn
           |> get("/api/autolaunch/v1/auctions/#{missing_id}")
           |> json_response(404) == %{
             "error" => %{"code" => "not_found", "message" => "Auction not found."}
           }

    routes = AshPlatformWeb.Router.__routes__()

    assert Enum.any?(routes, fn route ->
             route.verb == :get and route.path == "/api/autolaunch/v1/auctions" and
               route.plug == AshPlatformWeb.AutolaunchAuctionController and
               route.plug_opts == :index
           end)

    assert Enum.any?(routes, fn route ->
             route.verb == :get and route.path == "/api/autolaunch/v1/auctions/:id" and
               route.plug == AshPlatformWeb.AutolaunchAuctionController and
               route.plug_opts == :show
           end)
  end

  test "GET applies public modes, ordering, limits, and the auction field allowlist", %{
    conn: conn
  } do
    now = DateTime.utc_now()
    older = auction!("Older", :active, DateTime.add(now, -60, :second))
    newer = auction!("Newer", :active, now)
    graduated = auction!("Graduated", :graduated, DateTime.add(now, -30, :second))
    failed = auction!("Failed", :failed, DateTime.add(now, -20, :second))

    assert %{"data" => [oldest, newest]} =
             conn
             |> get("/api/autolaunch/v1/auctions?mode=live&sort=oldest&limit=2")
             |> json_response(200)

    assert Enum.map([oldest, newest], & &1["id"]) == [older.id, newer.id]

    assert Map.keys(newest) |> Enum.sort() ==
             ~w(featured id opened_at state summary title)

    assert newest == %{
             "id" => newer.id,
             "title" => "Newer",
             "summary" => nil,
             "featured" => false,
             "state" => "active",
             "opened_at" => DateTime.to_iso8601(now)
           }

    for {mode, expected_id} <- [
          {"graduated", graduated.id},
          {"failed_minimum", failed.id},
          {"biddable", newer.id}
        ] do
      assert %{"data" => [%{"id" => ^expected_id} | _]} =
               conn
               |> get("/api/autolaunch/v1/auctions?mode=#{mode}&limit=1")
               |> json_response(200)
    end

    assert %{"data" => detail} =
             conn
             |> get("/api/autolaunch/v1/auctions/#{newer.id}")
             |> json_response(200)

    assert detail == newest
  end

  test "GET clamps both limit edges and rejects undocumented or invalid query values", %{
    conn: conn
  } do
    injected =
      Plug.Conn.put_private(
        conn,
        :autolaunch_auction_controller_autolaunch,
        RecordingAutolaunch
      )

    assert injected
           |> get("/api/autolaunch/v1/auctions?mode=graduated&sort=oldest&limit=0")
           |> json_response(200) == %{"data" => []}

    assert_received {:list_public_auctions, "graduated", "oldest", 1}

    assert injected
           |> get("/api/autolaunch/v1/auctions?limit=51")
           |> json_response(200) == %{"data" => []}

    assert_received {:list_public_auctions, "all", "newest", 50}

    for path <- [
          "/api/autolaunch/v1/auctions?cursor=next",
          "/api/autolaunch/v1/auctions?mode=created",
          "/api/autolaunch/v1/auctions?sort=market_cap_desc",
          "/api/autolaunch/v1/auctions?limit=1.5",
          "/api/autolaunch/v1/auctions/#{Ash.UUID.generate()}?limit=1"
        ] do
      assert conn |> get(path) |> json_response(400) == invalid_request()
    end
  end

  test "GET hides domain failures behind the canonical error envelope", %{conn: conn} do
    injected =
      Plug.Conn.put_private(
        conn,
        :autolaunch_auction_controller_autolaunch,
        FailingAutolaunch
      )

    for path <- [
          "/api/autolaunch/v1/auctions",
          "/api/autolaunch/v1/auctions/#{Ash.UUID.generate()}"
        ] do
      response = get(injected, path)

      assert json_response(response, 500) == %{
               "error" => %{
                 "code" => "internal_error",
                 "message" => "The request could not be completed."
               }
             }

      refute response.resp_body =~ "sentinel"
      refute response.resp_body =~ "private details"
    end
  end

  test "cookies and bearer headers do not affect public auction reads", %{conn: conn} do
    auction = auction!("Public", :active, DateTime.utc_now())
    path = "/api/autolaunch/v1/auctions/#{auction.id}"

    anonymous = conn |> get(path) |> json_response(200)

    credentialed =
      conn
      |> put_req_cookie("_ash_platform_key", "not-a-session")
      |> put_req_header("authorization", "Bearer not-an-agent-token")
      |> get(path)
      |> json_response(200)

    assert anonymous == credentialed
  end

  test "a malformed auction identifier uses the public not-found envelope", %{conn: conn} do
    assert conn
           |> get("/api/autolaunch/v1/auctions/not-a-uuid")
           |> json_response(404) == %{
             "error" => %{"code" => "not_found", "message" => "Auction not found."}
           }
  end

  defp auction!(title, state, opened_at) do
    Autolaunch.import_auction!(title, nil, false, state, opened_at, actor: %System{})
  end

  defp invalid_request do
    %{
      "error" => %{
        "code" => "invalid_request",
        "message" => "The query parameters are invalid."
      }
    }
  end
end
