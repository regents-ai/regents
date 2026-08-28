defmodule AshPlatformWeb.AutolaunchTokenControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch
  alias AshPlatform.TestAutolaunchTreasuryChainClient, as: TreasuryClient

  defmodule RecordingAutolaunch do
    def list_public_tokens(limit, actor: nil) do
      send(self(), {:list_public_tokens, limit})
      {:ok, []}
    end
  end

  defmodule FailingAutolaunch do
    def list_public_tokens(_limit, actor: nil), do: {:error, {:sentinel, "private details"}}
  end

  test "GET routes an empty public token list", %{conn: conn} do
    assert conn |> get("/api/autolaunch/v1/tokens") |> json_response(200) == %{"data" => []}

    assert Enum.any?(AshPlatformWeb.Router.__routes__(), fn route ->
             route.verb == :get and route.path == "/api/autolaunch/v1/tokens" and
               route.plug == AshPlatformWeb.AutolaunchTokenController and
               route.plug_opts == :index
           end)
  end

  test "GET returns newest tokens through the explicit field allowlist", %{conn: conn} do
    auction = auction!()
    now = DateTime.utc_now()

    token =
      Autolaunch.import_token!(
        auction.id,
        "Newest Token",
        "NEW",
        "Public token summary.",
        now,
        1,
        actor: %System{}
      )

    assert %{"data" => [public]} =
             conn
             |> get("/api/autolaunch/v1/tokens?limit=1")
             |> json_response(200)

    assert Map.keys(public) |> Enum.sort() ==
             ~w(auction_id graduated_at id name subject_id summary symbol top_rank treasury_security)

    assert public == %{
             "id" => token.id,
             "auction_id" => auction.id,
             "subject_id" => nil,
             "name" => "Newest Token",
             "symbol" => "NEW",
             "summary" => "Public token summary.",
             "graduated_at" => DateTime.to_iso8601(now),
             "top_rank" => 1,
             "treasury_security" => nil
           }
  end

  test "GET loads a token's auction-bound report as the same fail-closed projection", %{
    conn: conn
  } do
    report =
      TreasuryClient.seed_verified!("0x9999999999999999999999999999999999999999")

    auction = auction!()
    Autolaunch.set_auction_treasury_security_report!(auction, report.id, actor: %System{})

    token =
      Autolaunch.import_token!(
        auction.id,
        "Bound Token",
        "BOUND",
        nil,
        DateTime.utc_now(),
        nil,
        actor: %System{}
      )

    assert %{"data" => tokens} =
             conn |> get("/api/autolaunch/v1/tokens") |> json_response(200)

    listed_token = Enum.find(tokens, &(&1["id"] == token.id))

    assert %{"data" => auction_detail} =
             conn
             |> get("/api/autolaunch/v1/auctions/#{auction.id}")
             |> json_response(200)

    assert listed_token["treasury_security"] == auction_detail["treasury_security"]
    assert listed_token["treasury_security"]["id"] == report.id

    assert listed_token["treasury_security"]["verification_state"] ==
             "awaiting_current_chain_confirmation"

    assert listed_token["treasury_security"]["verification_reason"] ==
             "projector_refresh_not_integrated"
  end

  test "GET clamps both limit edges and rejects undocumented or invalid query values", %{
    conn: conn
  } do
    injected =
      Plug.Conn.put_private(
        conn,
        :autolaunch_token_controller_autolaunch,
        RecordingAutolaunch
      )

    assert injected
           |> get("/api/autolaunch/v1/tokens?limit=0")
           |> json_response(200) == %{"data" => []}

    assert_received {:list_public_tokens, 1}

    assert injected
           |> get("/api/autolaunch/v1/tokens?limit=101")
           |> json_response(200) == %{"data" => []}

    assert_received {:list_public_tokens, 100}

    for path <- [
          "/api/autolaunch/v1/tokens?cursor=next",
          "/api/autolaunch/v1/tokens?limit=1.5"
        ] do
      assert conn |> get(path) |> json_response(400) == %{
               "error" => %{
                 "code" => "invalid_request",
                 "message" => "The query parameters are invalid."
               }
             }
    end
  end

  test "GET hides domain failures behind the canonical error envelope", %{conn: conn} do
    response =
      conn
      |> Plug.Conn.put_private(
        :autolaunch_token_controller_autolaunch,
        FailingAutolaunch
      )
      |> get("/api/autolaunch/v1/tokens")

    assert json_response(response, 500) == %{
             "error" => %{
               "code" => "internal_error",
               "message" => "The request could not be completed."
             }
           }

    refute response.resp_body =~ "sentinel"
    refute response.resp_body =~ "private details"
  end

  test "cookies and bearer headers do not affect the public token list", %{conn: conn} do
    auction = auction!()

    Autolaunch.import_token!(
      auction.id,
      "Public Token",
      "PUB",
      nil,
      DateTime.utc_now(),
      nil,
      actor: %System{}
    )

    anonymous = conn |> get("/api/autolaunch/v1/tokens") |> json_response(200)

    credentialed =
      conn
      |> put_req_cookie("_ash_platform_key", "not-a-session")
      |> put_req_header("authorization", "Bearer not-an-agent-token")
      |> get("/api/autolaunch/v1/tokens")
      |> json_response(200)

    assert anonymous == credentialed
  end

  defp auction! do
    Autolaunch.import_auction!(
      "Token auction",
      nil,
      false,
      :graduated,
      DateTime.utc_now(),
      actor: %System{}
    )
  end
end
