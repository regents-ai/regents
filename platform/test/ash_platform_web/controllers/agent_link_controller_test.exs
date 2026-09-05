defmodule AshPlatformWeb.AgentLinkControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Formation}
  alias AshPlatform.Actors.{Human, System}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"
  @other_wallet "0x3333333333333333333333333333333333333333"
  @now ~U[2026-08-04 12:00:00.000000Z]

  setup do
    previous_clock = Application.get_env(:ash_platform, :agent_pairing_clock)
    Application.put_env(:ash_platform, :agent_pairing_clock, fn -> @now end)
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)
    AshPlatform.AgentAuth.ClaimRateLimiter.reset()

    on_exit(fn ->
      restore(:agent_pairing_clock, previous_clock)
      Process.delete(:agent_verification_result)
      Process.delete(:capture_agent_verification_calls)
    end)

    :ok
  end

  test "a verified signed claim binds the agent and returns the public link", %{conn: conn} do
    {_account, actor, regent} = account_and_regent!("happy", @wallet)
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)
    Process.put(:agent_verification_result, {:ok, identity("happy")})
    Process.put(:capture_agent_verification_calls, true)

    path = claim_path(regent)

    response =
      conn
      |> put_req_header("content-type", "text/plain")
      |> put_req_header("signature", "test-signature")
      |> post(path, issued.code)
      |> json_response(201)

    assert response["data"]["regent_id"] == regent.id
    assert response["data"]["agent_id"] == "agent-happy"
    assert response["data"]["registry_address"] == @registry
    assert response["data"]["wallet"] == @wallet
    refute Map.has_key?(response["data"], "human_account_id")

    assert_received {:agent_verification, envelope}
    assert envelope.method == "POST"
    assert envelope.path == path
    assert envelope.body == issued.code
    assert envelope.headers["signature"] == "test-signature"

    assert {:ok, [link]} = Formation.list_my_agent_links(regent.id, actor: actor)
    assert link.id == response["data"]["id"]
  end

  test "an unverified or replayed signed request is rejected before code consumption", %{
    conn: conn
  } do
    {_account, actor, regent} = account_and_regent!("replay", @wallet)
    first_code = Formation.issue_agent_pairing_code!(regent.id, actor: actor)
    Process.put(:agent_verification_result, {:error, :verification_failed})

    assert conn
           |> raw_claim(regent, first_code.code)
           |> json_response(401) == verification_failed()

    Process.put(:agent_verification_result, {:ok, identity("first")})
    assert conn |> recycle() |> raw_claim(regent, first_code.code) |> response(201)

    Process.put(:agent_verification_result, {:error, :replayed_request})

    assert conn
           |> recycle()
           |> raw_claim(regent, first_code.code)
           |> json_response(401) == verification_failed()

    assert {:ok, [link]} = Formation.list_my_agent_links(regent.id, actor: actor)
    assert link.agent_id == "agent-first"
  end

  test "expired, reused, and unknown codes all return the same closed response", %{conn: conn} do
    {_account, actor, regent} = account_and_regent!("invalid", @wallet)
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)
    Process.put(:agent_verification_result, {:ok, identity("used")})

    assert conn |> raw_claim(regent, issued.code) |> response(201)

    for code <- [issued.code, "unknown-pairing-code"] do
      Process.put(:agent_verification_result, {:ok, identity("retry-#{code}")})

      assert conn
             |> recycle()
             |> raw_claim(regent, code)
             |> json_response(400) == pairing_failed()
    end

    {_other, other_actor, other_regent} = account_and_regent!("expired", @other_wallet)
    expired = Formation.issue_agent_pairing_code!(other_regent.id, actor: other_actor)

    Application.put_env(:ash_platform, :agent_pairing_clock, fn ->
      DateTime.add(@now, 601, :second)
    end)

    Process.put(:agent_verification_result, {:ok, identity("expired")})

    assert conn
           |> recycle()
           |> raw_claim(other_regent, expired.code)
           |> json_response(400) == pairing_failed()
  end

  test "a code issued for human A cannot bind against human B's Regent", %{conn: conn} do
    {_first, first_actor, first_regent} = account_and_regent!("human-a", @wallet)
    {_second, second_actor, second_regent} = account_and_regent!("human-b", @other_wallet)
    issued = Formation.issue_agent_pairing_code!(first_regent.id, actor: first_actor)
    Process.put(:agent_verification_result, {:ok, identity("cross-account")})

    assert conn
           |> raw_claim(second_regent, issued.code)
           |> json_response(400) == pairing_failed()

    assert {:ok, []} = Formation.list_my_agent_links(first_regent.id, actor: first_actor)
    assert {:ok, []} = Formation.list_my_agent_links(second_regent.id, actor: second_actor)
  end

  test "agent-link reads require the current owner session", %{conn: conn} do
    {owner, actor, regent} = account_and_regent!("read-owner", @wallet)
    {other, _other_actor, _other_regent} = account_and_regent!("read-other", @other_wallet)
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)

    Formation.claim_agent_link!(regent.id, issued.code, identity("listed"), actor: %System{})
    path = "/api/formation/v1/regents/#{regent.id}/agent-links"

    assert conn |> get(path) |> json_response(401) == %{"error" => "unauthorized"}

    assert conn
           |> recycle()
           |> init_test_session(%{human_account_id: other.id})
           |> get(path)
           |> json_response(404) == %{
             "error" => %{"code" => "not_found", "message" => "The Regent was not found."}
           }

    assert %{"data" => [link]} =
             conn
             |> recycle()
             |> init_test_session(%{human_account_id: owner.id})
             |> get(path)
             |> json_response(200)

    assert link["agent_id"] == "agent-listed"
  end

  test "claim admission allows ten attempts per minute and isolates budgets by remote IP", %{
    conn: conn
  } do
    {_account, _actor, regent} = account_and_regent!("rate-limit", @wallet)
    Process.put(:agent_verification_result, {:error, :verification_failed})
    Process.put(:capture_agent_verification_calls, true)

    for _attempt <- 1..10 do
      assert conn
             |> recycle()
             |> raw_claim(regent, "well-formed-code")
             |> json_response(401) == verification_failed()

      assert_received {:agent_verification, _envelope}
    end

    assert conn
           |> recycle()
           |> raw_claim(regent, "well-formed-code")
           |> json_response(429) == rate_limited()

    refute_received {:agent_verification, _envelope}

    assert conn
           |> recycle()
           |> from_ip({10, 0, 0, 2})
           |> raw_claim(regent, "well-formed-code")
           |> json_response(401) == verification_failed()

    assert_received {:agent_verification, _envelope}
  end

  test "invalid UTF-8 fails closed before verification", %{conn: conn} do
    {_account, _actor, regent} = account_and_regent!("invalid-utf8", @wallet)
    Process.put(:capture_agent_verification_calls, true)

    assert conn |> raw_claim(regent, <<255>>) |> json_response(400) == pairing_failed()
    refute_received {:agent_verification, _envelope}
  end

  test "uppercase Regent UUIDs work for both claim and owner read", %{conn: conn} do
    {account, actor, regent} = account_and_regent!("uppercase-uuid", @wallet)
    issued = Formation.issue_agent_pairing_code!(regent.id, actor: actor)
    Process.put(:agent_verification_result, {:ok, identity("uppercase")})
    uppercase_id = String.upcase(regent.id)

    assert conn
           |> put_req_header("content-type", "text/plain")
           |> put_req_header("signature", "test-signature")
           |> post(claim_path(uppercase_id), issued.code)
           |> response(201)

    assert %{"data" => [%{"agent_id" => "agent-uppercase"}]} =
             conn
             |> recycle()
             |> init_test_session(%{human_account_id: account.id})
             |> get("/api/formation/v1/regents/#{uppercase_id}/agent-links")
             |> json_response(200)
  end

  test "only the two canonical API routes are admitted" do
    routes = AshPlatformWeb.Router.__routes__()

    assert Enum.any?(routes, fn route ->
             route.verb == :get and
               route.path == "/api/formation/v1/regents/:regent_id/agent-links"
           end)

    assert Enum.any?(routes, fn route ->
             route.verb == :post and
               route.path == "/api/formation/v1/regents/:regent_id/agent-links/claim"
           end)
  end

  defp raw_claim(conn, regent, code) do
    conn
    |> put_req_header("content-type", "text/plain")
    |> put_req_header("signature", "test-signature")
    |> post(claim_path(regent), code)
  end

  defp claim_path(%{id: id}), do: claim_path(id)

  defp claim_path(regent_id),
    do: "/api/formation/v1/regents/#{regent_id}/agent-links/claim"

  defp from_ip(conn, remote_ip), do: %{conn | remote_ip: remote_ip}

  defp account_and_regent!(suffix, wallet) do
    unique = Elixir.System.unique_integer([:positive])

    account =
      Accounts.register_verified!(
        "did:privy:agent-link-controller:#{suffix}:#{unique}",
        wallet,
        [wallet],
        actor: %System{}
      )

    actor = %Human{human_account_id: account.id}

    regent =
      Formation.form_regent!("agent-link-#{suffix}-#{unique}", "Agent Link #{suffix}",
        actor: actor
      )

    {account, actor, regent}
  end

  defp identity(suffix) do
    %{
      agent_id: "agent-#{suffix}",
      registry_address: @registry,
      token_id: "7",
      wallet: @wallet
    }
  end

  defp pairing_failed do
    %{
      "error" => %{
        "code" => "pairing_failed",
        "message" => "The pairing code could not be used."
      }
    }
  end

  defp verification_failed do
    %{
      "error" => %{
        "code" => "verification_failed",
        "message" => "The signed agent request could not be verified."
      }
    }
  end

  defp rate_limited do
    %{
      "error" => %{
        "code" => "rate_limited",
        "message" => "Too many pairing attempts. Please wait and try again."
      }
    }
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
