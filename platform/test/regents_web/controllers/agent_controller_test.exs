defmodule RegentsWeb.AgentControllerTest do
  use RegentsWeb.ConnCase, async: false

  alias Regents.{Accounts, Agents}
  alias Regents.Actors.{Human, System}

  @agent_wallet "0x2222222222222222222222222222222222222222"
  @now ~U[2026-08-04 12:00:00.000000Z]

  setup do
    previous_clock = Application.fetch_env!(:regents, :agent_pairing_clock)
    Application.put_env(:regents, :agent_pairing_clock, fn -> @now end)
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)
    Regents.RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:regents, :agent_pairing_clock, previous_clock)
      Regents.RateLimiter.reset()
    end)

    :ok
  end

  test "a signed pairing request joins the person's account and returns the agent", %{conn: conn} do
    actor = person!()
    issued = Agents.issue_pairing_code!(actor: actor)
    Process.put(:agent_verification_result, {:ok, %{wallet: @agent_wallet}})
    Process.put(:capture_agent_verification_calls, true)

    body = Jason.encode!(%{code: issued.code, name: "Sol", harness: "hermes"})

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("signature", "test-signature")
      |> post("/api/agents/v1/pair", body)
      |> json_response(201)

    assert response == %{
             "data" => %{
               "name" => "Sol",
               "harness" => "hermes",
               "wallet" => @agent_wallet,
               "paired_at" => DateTime.to_iso8601(@now),
               "last_contact_at" => DateTime.to_iso8601(@now)
             }
           }

    # The signature covers the exact bytes the agent sent.
    assert_received {:agent_verification, envelope}
    assert envelope.method == "POST"
    assert envelope.path == "/api/agents/v1/pair"
    assert envelope.body == body
    assert envelope.headers["signature"] == "test-signature"

    assert {:ok, [%{name: "Sol"}]} = Agents.list_my_agents(actor: actor)
  end

  test "an unverified request pairs nothing and leaves the code usable", %{conn: conn} do
    actor = person!()
    issued = Agents.issue_pairing_code!(actor: actor)

    assert conn |> pair(issued.code, "hermes") |> json_response(401) == %{
             "error" => %{
               "code" => "verification_failed",
               "message" => "The signed agent request could not be verified.",
               "hint" =>
                 "Sign the request with your agent key as the docs describe, then send it again."
             }
           }

    Process.put(:agent_verification_result, {:ok, %{wallet: @agent_wallet}})
    assert conn |> recycle() |> pair(issued.code, "hermes") |> response(201)
  end

  test "a bad code, an unknown harness or extra fields cannot pair", %{conn: conn} do
    actor = person!()
    issued = Agents.issue_pairing_code!(actor: actor)
    Process.put(:agent_verification_result, {:ok, %{wallet: @agent_wallet}})

    failed = %{
      "error" => %{
        "code" => "pairing_failed",
        "message" => "The pairing code could not be used.",
        "hint" =>
          "Ask your person for a new pairing code. Each code works once and expires ten minutes after it was made."
      }
    }

    for body <- [
          %{code: "not-a-real-code", name: "Sol", harness: "hermes"},
          %{code: issued.code, name: "Sol", harness: "claude"},
          %{code: issued.code, name: "Sol", harness: "hermes", wallet: "0x1"},
          %{code: issued.code, name: "Sol"}
        ] do
      assert conn |> recycle() |> post_json("/api/agents/v1/pair", body) |> json_response(400) ==
               failed
    end

    assert {:ok, []} = Agents.list_my_agents(actor: actor)
  end

  test "pairing attempts from one address are limited, and each answer says what is left",
       %{conn: conn} do
    first = pair(conn, "code", "hermes")
    assert response(first, 401)
    assert get_resp_header(first, "ratelimit-policy") == [~s("pair";q=10;w=60)]
    assert [~s("pair";r=9;t=) <> _reset] = get_resp_header(first, "ratelimit")

    for _attempt <- 2..10 do
      assert conn |> recycle() |> pair("code", "hermes") |> response(401)
    end

    limited = conn |> recycle() |> pair("code", "hermes")

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

  test "a paired agent checks in; an unpaired one is told to ask for a code", %{conn: conn} do
    actor = person!()
    issued = Agents.issue_pairing_code!(actor: actor)
    Agents.pair_agent!(issued.code, @agent_wallet, "Sol", :hermes, actor: %System{})
    Process.put(:agent_verification_result, {:ok, %{wallet: @agent_wallet}})
    Process.put(:capture_agent_verification_calls, true)

    assert %{"data" => %{"name" => "Sol", "harness" => "hermes"} = agent} =
             conn |> get("/api/agents/v1/me") |> json_response(200)

    # A check-in is signed without a body, so none is sent to be checked.
    assert_received {:agent_verification, %{method: "GET", body: nil}}

    # A person who has set neither name yet.
    assert agent["account"] == %{"display_name" => nil, "ens_name" => nil}

    # The account is named as the person's own Account page names it.
    Regents.Repo.query!(
      "update regent_names.platform_human_users set display_name = 'Ada' where id = $1",
      [actor.human_account_id]
    )

    Accounts.put_ens_identity(actor.human_account_id, "ada.eth", nil, actor: %System{})

    assert %{"data" => %{"account" => %{"display_name" => "Ada", "ens_name" => "ada.eth"}}} =
             conn |> recycle() |> get("/api/agents/v1/me") |> json_response(200)

    Process.put(:agent_verification_result, {:ok, %{wallet: "0x" <> String.duplicate("4", 40)}})

    assert conn |> recycle() |> get("/api/agents/v1/me") |> json_response(404) == %{
             "error" => %{
               "code" => "not_paired",
               "message" => "This agent is not paired with an account.",
               "hint" => "Ask your person for a pairing code, then pair again."
             }
           }

    Process.delete(:agent_verification_result)
    assert conn |> recycle() |> get("/api/agents/v1/me") |> response(401)
  end

  defp pair(conn, code, harness),
    do: post_json(conn, "/api/agents/v1/pair", %{code: code, name: "Sol", harness: harness})

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  defp person! do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")

    account =
      Accounts.register_verified!("did:privy:agent-api:#{unique}", wallet, [wallet],
        actor: %System{}
      )

    %Human{human_account_id: account.id}
  end
end
