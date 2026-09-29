defmodule RegentsWeb.AgentRequestsTest do
  use RegentsWeb.ConnCase, async: false

  alias RegentAgents.Person
  alias Regents.Accounts
  alias Regents.Actors.System

  @agent_wallet "0x2222222222222222222222222222222222222222"

  setup do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
  end

  test "an agent pairs with the code its person made here, signed for Regents", %{conn: conn} do
    {person, _account_id} = person!()
    issued = RegentAgents.issue_pairing_code!(actor: person)
    siwa_verifies(@agent_wallet)

    body = Jason.encode!(%{code: issued.code, name: "Sol", harness: "claude_code"})

    assert %{"data" => %{"name" => "Sol", "harness" => "claude_code", "wallet" => @agent_wallet}} =
             conn
             |> put_req_header("content-type", "application/json")
             |> post("/api/agents/v1/pair", body)
             |> json_response(201)

    # The signature covers the exact bytes the agent sent, for this site.
    assert_received {:verified, ["regents-test"], %{"path" => "/api/agents/v1/pair"} = envelope}
    assert envelope["body"] == body

    assert {:ok, [%{name: "Sol", harness: :claude_code}]} =
             RegentAgents.list_my_agents(actor: person)
  end

  test "a check-in names the account as the person's own Account page names it",
       %{conn: conn} do
    {person, account_id} = person!()
    issued = RegentAgents.issue_pairing_code!(actor: person)
    siwa_verifies(@agent_wallet)
    assert conn |> pair(issued.code) |> response(201)

    assert %{"data" => %{"name" => "Sol", "account" => account}} =
             conn |> recycle() |> get("/api/agents/v1/me") |> json_response(200)

    assert account == %{"display_name" => nil, "ens_name" => nil}

    Regents.Repo.query!(
      "update regent_names.platform_human_users set display_name = 'Ada' where id = $1",
      [account_id]
    )

    Accounts.put_ens_identity(account_id, "ada.eth", nil, actor: %System{})

    assert %{"data" => %{"account" => %{"display_name" => "Ada", "ens_name" => "ada.eth"}}} =
             conn |> recycle() |> get("/api/agents/v1/me") |> json_response(200)
  end

  test "pairing attempts from one address are limited, and each answer says what is left",
       %{conn: conn} do
    siwa_refuses()

    first = pair(conn, "code")
    assert response(first, 401)
    assert get_resp_header(first, "ratelimit-policy") == [~s("pair";q=10;w=60)]
    assert [~s("pair";r=9;t=) <> _reset] = get_resp_header(first, "ratelimit")

    for _attempt <- 2..10 do
      assert conn |> recycle() |> pair("code") |> response(401)
    end

    limited = conn |> recycle() |> pair("code")

    assert json_response(limited, 429) == %{
             "error" => %{
               "code" => "rate_limited",
               "message" => "Too many requests.",
               "hint" => "Wait the number of seconds in Retry-After, then try again."
             }
           }

    assert [~s("pair";r=0;t=) <> _reset] = get_resp_header(limited, "ratelimit")
    assert [retry_after] = get_resp_header(limited, "retry-after")
    assert String.to_integer(retry_after) in 1..60

    # Check-ins count against their own budget.
    check_in = conn |> recycle() |> get("/api/agents/v1/me")
    assert response(check_in, 401)
    assert get_resp_header(check_in, "ratelimit-policy") == [~s("check-in";q=60;w=60)]
  end

  defp pair(conn, code) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/agents/v1/pair", Jason.encode!(%{code: code, name: "Sol", harness: "hermes"}))
  end

  # The sign-in service verifies the request and names the key that signed it.
  defp siwa_verifies(wallet) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      audience = Plug.Conn.get_req_header(conn, "x-siwa-audience")
      send(self(), {:verified, audience, Jason.decode!(body)})

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => wallet,
            "chain_id" => 8453,
            "audience" => "regents-test"
          }
        }
      })
    end)
  end

  defp siwa_refuses do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"error" => %{"code" => "http_signature_invalid", "message" => "no"}})
    end)
  end

  defp person! do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")
    did = "did:privy:agent-api:#{unique}"
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {%Person{privy_user_id: did}, account.id}
  end
end
