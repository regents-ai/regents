defmodule RegentsWeb.MessagesPagesTest do
  # The pages around a message left for the site's team:
  # - /agents carries the Agent Message dialog for the topic agents, with a
  #   paste-ready text for each way an agent connects, and the form only for a
  #   signed-in person (test/browser/agent_message.spec.ts leaves one through it);
  # - /admin/messages shows the team every message, newest first, and is the
  #   not-found page for anyone who is not one of the site's admins.
  use RegentsWeb.ConnCase, async: false

  alias Regents.{Accounts, Messages}
  alias Regents.Actors.{Human, System}
  alias RegentsWeb.Components.AgentMessage

  setup do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
  end

  test "/agents offers the Agent Message texts to everyone, and the form only to a signed-in person",
       %{conn: conn} do
    signed_out = page(conn, "/agents")

    texts =
      signed_out
      |> LazyHTML.query("#agents-message .agent-message__text pre code")
      |> Enum.map(&LazyHTML.text/1)

    assert texts == Enum.map(AgentMessage.texts("agents"), & &1.text)
    assert [cli, webmcp] = texts
    assert cli =~ "regents protocol messages leave agents"
    assert webmcp =~ "messages_leave"

    copied =
      signed_out
      |> LazyHTML.query("#agents-message [data-copy-target]")
      |> LazyHTML.attribute("data-copy-target")

    assert copied == ["agents-message-text-cli", "agents-message-text-webmcp"]
    assert Enum.empty?(LazyHTML.query(signed_out, "#agents-message-person-form"))

    account = account!()
    signed_in = page(init_test_session(conn, %{human_account_id: account.id}), "/agents")
    assert Enum.count(LazyHTML.query(signed_in, "#agents-message-person-form")) == 1

    # Another agent's page carries none.
    assert Enum.empty?(LazyHTML.query(page(conn, "/agents/hermes"), "#agents-message"))
  end

  test "/admin/messages shows the team every message, and is not found for anyone else",
       %{conn: conn} do
    account = account!()
    {:ok, older} = leave(account, "agents", "First")
    {:ok, newer} = leave(account, "watchdog", "Second")
    signed_in = init_test_session(conn, %{human_account_id: account.id})

    assert conn |> get("/admin/messages") |> response(404)
    assert signed_in |> get("/admin/messages") |> response(404)

    put_admins([account.privy_user_id])
    page = page(signed_in, "/admin/messages")

    ids = page |> LazyHTML.query("#admin-messages > li") |> LazyHTML.attribute("id")
    assert Enum.take(ids, 2) == ["message-#{newer.id}", "message-#{older.id}"]
    assert LazyHTML.text(page) =~ "Second"
  end

  defp leave(account, topic, body),
    do:
      Messages.leave_message(%{topic: topic, body: body},
        actor: %Human{human_account_id: account.id},
        context: %{client_key: Ecto.UUID.generate()}
      )

  defp page(conn, path),
    do:
      conn
      |> put_req_header("accept", "text/html")
      |> get(path)
      |> html_response(200)
      |> LazyHTML.from_document()

  defp account! do
    did = "did:privy:messages-page-" <> Ecto.UUID.generate()
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
  end

  defp put_admins(admins) do
    old = Application.fetch_env!(:regent_credits, :admins)
    Application.put_env(:regent_credits, :admins, admins)
    on_exit(fn -> Application.put_env(:regent_credits, :admins, old) end)
  end
end
