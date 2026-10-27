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

    # The sign-in server gets the digest of the exact bytes the agent sent, for this site.
    assert_received {:verified, ["regents-test"], %{"path" => "/api/agents/v1/pair"} = envelope}
    assert envelope["body_digest"] == Siwa.content_digest_for_body(body)

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

  # A signed agent asking who it is gets its status, what it may do here in that
  # status and its next step, in each of the three states.
  test "an agent nobody paired is told it is not paired and how to pair", %{conn: conn} do
    siwa_verifies(@agent_wallet)

    data = whoami(conn)

    assert %{"authenticated" => true, "status" => "not_paired", "pairing" => nil} = data
    assert data["agent"]["wallet"] == @agent_wallet
    assert data["allowed"] == allowed("not_paired")
    assert data["next_step"] == RegentAgents.HTTP.next_step("not_paired")
  end

  test "an agent whose person has never signed in here is told so", %{conn: conn} do
    elsewhere = %Person{privy_user_id: "did:privy:elsewhere:#{Elixir.System.unique_integer()}"}
    issued = RegentAgents.issue_pairing_code!(actor: elsewhere)

    pairing =
      RegentAgents.pair_agent!(issued.code, "Sol", :codex,
        actor: %RegentAgents.Agent{wallet: @agent_wallet}
      )

    siwa_verifies(@agent_wallet)

    assert %{"status" => "person_not_here", "pairing" => %{"id" => id}} = data = whoami(conn)
    assert id == pairing.id
    assert data["allowed"] == allowed("person_not_here")
    assert data["next_step"] == RegentAgents.HTTP.next_step("person_not_here")
  end

  test "a paired agent whose person signed in here is told it is paired", %{conn: conn} do
    {person, _account_id} = person!()
    issued = RegentAgents.issue_pairing_code!(actor: person)
    siwa_verifies(@agent_wallet)
    assert %{"data" => %{"id" => id}} = conn |> pair(issued.code) |> json_response(201)

    assert %{"status" => "paired", "pairing" => %{"id" => ^id}, "next_step" => nil} =
             data = conn |> recycle() |> whoami()

    assert data["allowed"] == allowed("paired")
  end

  # The pair and check-in answers carry the pairing id the contract lists.
  test "pairing and check-in name the same pairing id", %{conn: conn} do
    {person, _account_id} = person!()
    issued = RegentAgents.issue_pairing_code!(actor: person)
    siwa_verifies(@agent_wallet)

    assert %{"data" => %{"id" => id}} = conn |> pair(issued.code) |> json_response(201)
    assert {:ok, _uuid} = Ecto.UUID.cast(id)

    assert %{"data" => %{"id" => ^id}} =
             conn |> recycle() |> get("/api/agents/v1/me") |> json_response(200)
  end

  # A Credits history cursor that is not valid gets the shared 422 refusal, not
  # a "try again" answer.
  test "a bad Credits history cursor is refused with the shared words", %{conn: conn} do
    {person, _account_id} = person!()
    issued = RegentAgents.issue_pairing_code!(actor: person)
    siwa_verifies(@agent_wallet)
    assert conn |> pair(issued.code) |> response(201)

    history = fn body ->
      conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post("/api/agent/v1/credits/history", Jason.encode!(body))
    end

    assert %{"entries" => [], "pagination" => %{"has_more" => false}} =
             history.(%{}) |> json_response(200)

    for body <- [%{after: "not-a-cursor"}, %{after: "", extra: 1}] do
      assert history.(body) |> json_response(422) == %{
               "error" => %{
                 "code" => "invalid_cursor",
                 "message" => "That history cursor is invalid.",
                 "hint" =>
                   "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."
               }
             }
    end
  end

  test "pairing attempts from one address are limited, and each answer says what is left",
       %{conn: conn} do
    siwa_refuses()

    first = pair(conn, "code")
    assert response(first, 401)

    assert get_resp_header(first, "ratelimit-policy") ==
             [~s("default";q=120;w=60, "pair";q=10;w=60)]

    assert [~s("default";r=119;t=) <> rest] = get_resp_header(first, "ratelimit")
    assert rest =~ ~s(, "pair";r=9;t=)

    for _attempt <- 2..10 do
      assert conn |> recycle() |> pair("code") |> response(401)
    end

    limited = conn |> recycle() |> pair("code")

    assert json_response(limited, 429) == %{
             "error" => %{
               "code" => "too_many_requests",
               "message" => "Too Many Requests",
               "hint" => "Wait the number of seconds in Retry-After, then send the request again."
             }
           }

    assert [retry_after] = get_resp_header(limited, "retry-after")
    assert String.to_integer(retry_after) in 1..60

    # Everything else counts against the default budget only.
    check_in = conn |> recycle() |> get("/api/agents/v1/me")
    assert response(check_in, 401)
    assert get_resp_header(check_in, "ratelimit-policy") == [~s("default";q=120;w=60)]
    assert [~s("default";r=108;t=) <> _reset] = get_resp_header(check_in, "ratelimit")
  end

  test "the health check and the public API share one budget per address", %{conn: conn} do
    assert conn |> get("/healthz") |> get_resp_header("ratelimit-policy") ==
             [~s("default";q=120;w=60)]

    products = conn |> recycle() |> get("/api/v1/products")
    assert [~s("default";r=118;t=) <> _reset] = get_resp_header(products, "ratelimit")

    # A page is not counted.
    assert conn |> recycle() |> get("/docs") |> get_resp_header("ratelimit") == []
  end

  test "a body over a megabyte is refused before it is read", %{conn: conn} do
    body =
      Jason.encode!(%{code: String.duplicate("a", 1_000_000), name: "Sol", harness: "hermes"})

    {413, _headers, refusal} =
      assert_error_sent(413, fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/agents/v1/pair", body)
      end)

    assert %{"error" => %{"code" => _code}} = Jason.decode!(refusal)
  end

  defp whoami(conn) do
    conn |> get("/api/agents/v1/whoami") |> json_response(200) |> Map.fetch!("data")
  end

  defp allowed(status), do: Map.fetch!(Application.fetch_env!(:regent_agents, :allowed), status)

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
          },
          "agentRegistration" => nil,
          "agentBook" => nil
        }
      })
    end)
  end

  defp siwa_refuses do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        "error" => %{
          "code" => "http_signature_invalid",
          "message" => "The request signature does not match.",
          "hint" => "Sign the exact request you send, then send it again."
        }
      })
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
