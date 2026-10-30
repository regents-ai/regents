defmodule RegentsWeb.McpAgentTest do
  # The hosted MCP server at /mcp says who is calling as the agent access spec
  # (4.3) sets out, through this site's own endpoint, router and actions:
  # - every request carries an agent's signature or a connected app's token, never
  #   both, and a signature the sign-in service refuses is refused;
  # - a paired agent's signed call reads what the agent API reads, with the same
  #   answer;
  # - a query string, a page from another site, a batch, a body that is not JSON
  #   and any other method or address are refused in the site's shape, before
  #   any signature is checked;
  # - input a read cannot take gets the code HTTP gives it;
  # - one address gets the API's 120 requests a minute, and requests with a
  #   token share 600.
  # A connected app's own calls are in RegentsWeb.ClaudeConnectorTest. The
  # sign-in service is stubbed: it vouches for the wallet a request names when the
  # request carries the fixture proof. Each test calls from its own address, so it
  # spends its own rate budgets, not the rest of the suite's.
  use RegentsWeb.ConnCase, async: false

  import Plug.Test, only: [conn: 3]

  alias RegentAgents.Person
  alias Regents.Accounts
  alias Regents.Actors.System

  @reads [
    {"regents_account", :get, "/api/agent/v1/account"},
    {"regents_credits_balance", :get, "/api/agent/v1/credits/balance"},
    {"regents_credits_budget", :get, "/api/agent/v1/credits/budget"},
    {"regents_credits_history", :post, "/api/agent/v1/credits/history"},
    {"regents_points_summary", :get, "/api/agent/v1/points"}
  ]

  setup do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      headers = Jason.decode!(body)["headers"]

      if headers["x-siwa-signature"] == "fixture-proof" do
        wallet = headers["x-agent-wallet-address"]

        Req.Test.json(conn, %{
          "code" => "http_envelope_valid",
          "data" => %{
            "verified" => true,
            "walletAddress" => wallet,
            "agentBook" => nil,
            "agentRegistration" => nil,
            "principal" => %{
              "kind" => "wallet",
              "wallet_address" => wallet,
              "chain_id" => 8453,
              "audience" => "regents-test"
            }
          }
        })
      else
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{
          "error" => %{
            "code" => "http_signature_invalid",
            "message" => "Signature invalid",
            "hint" => "Sign again"
          }
        })
      end
    end)

    %{from: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}}
  end

  test "a signature and a token together are refused, and a token alone while connecting apps is off",
       %{from: from} do
    both = mcp(call("regents_account"), from: from, proof: wallet(), token: "a-token")
    assert both.status == 401
    assert error(both)["code"] == "ambiguous_credentials"

    token = mcp(call("regents_account"), from: from, token: "a-token")
    assert token.status == 401
    assert error(token)["code"] == "delegated_access_not_enabled"
  end

  test "a signature the sign-in service refuses is refused, even for a read", %{from: from} do
    refused = mcp(call("regents_account"), from: from, proof: wallet(), signature: "forged")
    assert refused.status == 401
    assert error(refused)["code"] == "http_signature_invalid"
  end

  test "every request needs a signature or a token, from the first one on", %{from: from} do
    initialize =
      rpc("initialize", %{
        "protocolVersion" => "2025-06-18",
        "capabilities" => %{},
        "clientInfo" => %{"name" => "t", "version" => "1"}
      })

    for body <- [initialize, rpc("tools/list"), call("regents_account")] do
      refused = mcp(body, from: from)
      assert refused.status == 401
      assert error(refused)["code"] == "agent_auth_required"
      assert get_resp_header(refused, "www-authenticate") == []
    end

    listed = mcp(rpc("tools/list"), from: from, proof: paired_wallet())

    assert Enum.sort(Enum.map(result(listed)["tools"], & &1["name"])) ==
             Enum.sort(Enum.map(@reads, &elem(&1, 0)))
  end

  test "an agent nobody paired is refused as on the agent API", %{from: from} do
    agent = wallet()
    refused = mcp(call("regents_account"), from: from, proof: agent)
    http = signed(conn(:get, "/api/agent/v1/account", nil), agent, from)

    assert {refused.status, error(refused)} == {http.status, error(http)}
  end

  test "each read answers as the agent API does, privately", %{from: from} do
    agent = paired_wallet()

    for {name, method, path} <- @reads do
      read = mcp(call(name), from: from, proof: agent)
      assert get_resp_header(read, "cache-control") == ["private, no-store"]
      assert %{"isError" => false, "structuredContent" => answer} = result(read)

      body = if method == :post, do: "{}"
      http = signed(conn(method, path, body), agent, from)
      assert http.status == 200, http.resp_body
      assert answer == Jason.decode!(http.resp_body)
    end
  end

  test "a query string is refused for every caller before anything else runs", %{from: from} do
    for opts <- [[], [proof: wallet()], [proof: wallet(), signature: "forged"], [token: "t"]] do
      refused = mcp(call("regents_account"), [from: from, query: "a=1"] ++ opts)
      assert refused.status == 400
      assert error(refused)["code"] == "unsupported_query"
    end
  end

  test "a page from another site is refused before any signature is checked", %{from: from} do
    agent = paired_wallet()

    for origin <- ["https://evil.example", "null"] do
      refused =
        mcp(call("regents_account"),
          from: from,
          origin: origin,
          proof: agent,
          signature: "forged"
        )

      assert refused.status == 403
      assert error(refused)["code"] == "origin_not_allowed"
    end

    own =
      mcp(call("regents_account"),
        from: from,
        origin: RegentsWeb.PublicDocuments.url(""),
        proof: agent
      )

    assert %{"isError" => false} = result(own)
  end

  test "one call a request: a batch is refused", %{from: from} do
    batch =
      mcp([call("regents_account"), call("regents_points_summary")], from: from, proof: wallet())

    assert batch.status == 400
    assert error(batch)["code"] == "batch_not_supported"
  end

  test "input a read cannot take is refused with the HTTP code, never a placeholder", %{
    from: from
  } do
    agent = paired_wallet()

    for {name, input, code} <- [
          {"regents_credits_history", %{after: 5}, "invalid_cursor"},
          {"regents_credits_history", %{after: ""}, "invalid_cursor"},
          {"regents_credits_history", %{after: nil}, "invalid_cursor"},
          {"regents_credits_history", %{after: "not-a-cursor"}, "invalid_cursor"},
          {"regents_credits_history", %{foo: 1}, "invalid_input"},
          {"regents_credits_history", "after", "invalid_input"},
          {"regents_account", %{foo: 1}, "invalid_input"},
          {"regents_points_summary", [], "invalid_input"}
        ] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               result(mcp(call(name, input), from: from, proof: agent))

      refute text =~ "%{"
      assert Jason.decode!(text)["error"]["code"] == code
    end
  end

  test "only POST /mcp is served; anything else answers in the site's shape", %{from: from} do
    for {method, path} <- [
          {:options, "/mcp"},
          {:put, "/mcp"},
          {:get, "/mcp"},
          {:post, "/mcp/anything"}
        ] do
      conn =
        conn(method, path, "{}")
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> @endpoint.call([])

      assert conn.status in [404, 405]
      assert %{"code" => _, "message" => _, "hint" => _} = error(conn)
    end

    stream =
      conn(:get, "/mcp", nil)
      |> Map.put(:remote_ip, from)
      |> put_req_header("accept", "text/event-stream")
      |> @endpoint.call([])

    assert stream.status == 405
    assert get_resp_header(stream, "allow") == ["POST"]

    form =
      conn(:post, "/mcp", "jsonrpc=2.0&method=tools%2Flist")
      |> Map.put(:remote_ip, from)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-siwa-signature", "fixture-proof")
      |> put_req_header("x-agent-wallet-address", wallet())
      |> @endpoint.call([])

    assert form.status == 415
    assert error(form)["hint"] =~ RegentsWeb.PublicDocuments.url("/docs")

    {413, _headers, body} =
      assert_error_sent(413, fn ->
        conn(:post, "/mcp", Jason.encode!(%{"padding" => String.duplicate("a", 70_000)}))
        |> Map.put(:remote_ip, from)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> @endpoint.call([])
      end)

    assert %{"error" => %{"code" => _}} = Jason.decode!(body)
  end

  test "one address gets 120 requests a minute here, as on the API", %{from: from} do
    statuses = for _ <- 1..121, do: mcp(rpc("tools/list"), from: from).status
    assert Enum.uniq(Enum.take(statuses, 120)) == [401]
    assert List.last(statuses) == 429
  end

  test "requests with a token share 600 a minute from one address, Claude's servers among them",
       %{from: from} do
    statuses =
      for _ <- 1..601, do: mcp(rpc("tools/list"), from: from, token: "not-a-token").status

    assert Enum.uniq(Enum.take(statuses, 600)) == [401]
    assert List.last(statuses) == 429
    assert mcp(rpc("tools/list"), from: from).status == 401
  end

  defp mcp(body, opts) do
    path = if opts[:query], do: "/mcp?" <> opts[:query], else: "/mcp"

    conn(:post, path, Jason.encode!(body))
    |> Map.put(:remote_ip, Keyword.fetch!(opts, :from))
    |> then(&if(opts[:origin], do: put_req_header(&1, "origin", opts[:origin]), else: &1))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> then(
      &if(opts[:proof],
        do: proof(&1, opts[:proof], opts[:signature] || "fixture-proof"),
        else: &1
      )
    )
    |> then(
      &if(opts[:token],
        do: put_req_header(&1, "authorization", "Bearer " <> opts[:token]),
        else: &1
      )
    )
    |> @endpoint.call([])
  end

  defp signed(conn, wallet, from) do
    conn
    |> Map.put(:remote_ip, from)
    |> put_req_header("content-type", "application/json")
    |> proof(wallet, "fixture-proof")
    |> @endpoint.call([])
  end

  defp proof(conn, wallet, signature) do
    conn
    |> put_req_header("x-siwa-signature", signature)
    |> put_req_header("x-agent-wallet-address", wallet)
  end

  # A tool listed with no inputs is called with empty arguments; one with
  # inputs takes them under `input`.
  defp call(name), do: rpc("tools/call", %{"name" => name, "arguments" => %{}})

  defp call(name, input),
    do: rpc("tools/call", %{"name" => name, "arguments" => %{"input" => input}})

  defp rpc(method, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

  defp result(conn), do: Jason.decode!(conn.resp_body)["result"]
  defp error(conn), do: Jason.decode!(conn.resp_body)["error"]

  # An agent's wallet, paired with a person who has signed in here.
  defp paired_wallet do
    unique = Elixir.System.unique_integer([:positive])
    did = "did:privy:mcp:#{unique}"
    person = wallet()
    agent = wallet()
    Accounts.register_verified!(did, person, [person], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %Person{privy_user_id: did})

    RegentAgents.pair_agent!(code.code, "Agent", :codex,
      actor: %RegentAgents.Agent{wallet: agent}
    )

    agent
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
