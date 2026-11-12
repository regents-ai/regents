defmodule RegentsWeb.MessagesApiTest do
  # A paired agent leaving a message for the site's team over signed HTTP
  # (`POST /api/v1/messages/{topic}`):
  # - it leaves one and gets its receipt, 201, as itself whatever the body says
  #   about the sender;
  # - its operation_id answers 200 with the first receipt, and 409
  #   idempotency_conflict for other text;
  # - input the action cannot take is 422 invalid_message with details;
  # - an agent nobody paired, an unsigned request and a refused signature leave
  #   nothing.
  # The sign-in service is stubbed: it vouches for the wallet each test names.
  use RegentsWeb.ConnCase, async: false

  alias Regents.Accounts
  alias Regents.Actors.System
  alias Regents.Messages.Message

  setup do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
    %{agent: wallet()}
  end

  test "a paired agent leaves a message as itself, and its operation_id answers it again",
       %{conn: conn, agent: agent} do
    account = paired!(conn, agent)
    key = Ecto.UUID.generate()

    body = %{
      body: "Hello team",
      reply_to: "agent@example.com",
      operation_id: key,
      agent_wallet_address: wallet(),
      human_account_id: 1,
      sender_name: "Someone else"
    }

    assert %{"receipt" => %{"id" => id, "topic" => "agents", "inserted_at" => _}} =
             conn |> leave("agents", body) |> json_response(201)

    # Read past the policies, which let only the site's admins read.
    message = Ash.get!(Message, id, authorize?: false)
    assert {message.body, message.reply_to} == {"Hello team", "agent@example.com"}
    assert {message.human_account_id, message.agent_wallet_address} == {account.id, agent}
    assert message.sender_name == Regents.PublicIdentity.label(account)

    assert %{"receipt" => %{"id" => ^id}} =
             conn |> recycle() |> leave("agents", body) |> json_response(200)

    assert %{"error" => %{"code" => "idempotency_conflict"}} =
             conn
             |> recycle()
             |> leave("agents", %{body: "Other text", operation_id: key})
             |> json_response(409)
  end

  test "input the action cannot take is refused with what to change", %{conn: conn, agent: agent} do
    paired!(conn, agent)
    count = count()

    too_long = %{body: String.duplicate("a", 2001), operation_id: Ecto.UUID.generate()}

    assert %{"error" => %{"code" => "invalid_message", "details" => [%{"field" => "body"}]}} =
             conn |> leave("agents", too_long) |> json_response(422)

    assert %{"error" => %{"code" => "invalid_message", "details" => [%{"field" => "topic"}]}} =
             conn
             |> recycle()
             |> leave("Not-A-Topic", %{body: "Hi", operation_id: Ecto.UUID.generate()})
             |> json_response(422)

    assert %{
             "error" => %{
               "code" => "invalid_message",
               "details" => [%{"field" => "operation_id"}]
             }
           } =
             conn |> recycle() |> leave("agents", %{body: "Hi"}) |> json_response(422)

    assert count() == count
  end

  test "an agent nobody paired, an unsigned request and a refused signature leave nothing",
       %{conn: conn, agent: agent} do
    body = %{body: "Hi", operation_id: Ecto.UUID.generate()}
    count = count()

    siwa_verifies(agent)

    assert %{"error" => %{"code" => "agent_not_paired"}} =
             conn |> leave("agents", body) |> json_response(403)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{
        "error" => %{"code" => "http_signature_invalid", "message" => "No.", "hint" => "Sign."}
      })
    end)

    assert conn |> recycle() |> leave("agents", body) |> json_response(401)
    assert count() == count
  end

  defp leave(conn, topic, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/messages/#{topic}", Jason.encode!(body))
  end

  # Counted past the policies, which let only the site's admins read.
  defp count, do: Message |> Ash.read!(authorize?: false) |> length()

  # The agent pairs with a person who signed in here, then the sign-in service
  # keeps vouching for its wallet.
  defp paired!(conn, agent) do
    did = "did:privy:messages-api:" <> Ecto.UUID.generate()
    person_wallet = wallet()
    account = Accounts.register_verified!(did, person_wallet, [person_wallet], actor: %System{})
    issued = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})
    siwa_verifies(agent)

    assert conn
           |> put_req_header("content-type", "application/json")
           |> post(
             "/api/agents/v1/pair",
             Jason.encode!(%{code: issued.code, name: "Sol", harness: "codex"})
           )
           |> response(201)

    account
  end

  defp siwa_verifies(wallet) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
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

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end
