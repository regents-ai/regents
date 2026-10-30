defmodule RegentsWeb.AgentOwnPictureTest do
  use RegentsWeb.ConnCase, async: false

  alias RegentAgents.Person
  alias Regents.Accounts
  alias Regents.Actors.System

  @wallet "0x2222222222222222222222222222222222222222"
  @other "0x3333333333333333333333333333333333333333"

  setup do
    Regents.RateLimiter.reset()
    on_exit(&Regents.RateLimiter.reset/0)
  end

  test "an agent sets and removes only its own picture, never one over 64 KB, and only while paired",
       %{conn: conn} do
    # Invariant: the agent's pairing names the picture it changes, so another agent
    # of the same person keeps theirs; a picture is re-made before it is kept, and
    # one too large is refused before it is opened.
    person = person!()
    siwa_verifies(@wallet)

    assert %{"data" => %{"id" => pairing_id}} =
             conn
             |> pair(RegentAgents.issue_pairing_code!(actor: person).code)
             |> json_response(201)

    sibling =
      RegentAgents.pair_agent!(
        RegentAgents.issue_pairing_code!(actor: person).code,
        "Sibling",
        :hermes,
        actor: %RegentAgents.Agent{wallet: @other}
      )

    {:ok, png} =
      640 |> Vix.Vips.Operation.black!(360, bands: 3) |> Vix.Vips.Image.write_to_buffer(".png")

    {:ok, theirs} = Regents.AgentPicture.make(png)
    {:ok, _picture} = RegentAgents.set_agent_picture(sibling.id, theirs, actor: person)
    send_picture = &signed(conn, :post, Jason.encode!(&1))

    set = send_picture.(%{picture: Base.encode64(png)})
    assert set.status == 200, set.resp_body
    url = URI.parse(Jason.decode!(set.resp_body)["picture"]["url"])
    assert url.path == "/agents/#{@wallet}/picture"

    shown = conn |> recycle() |> get(url.path <> "?" <> url.query)
    assert shown.status == 200
    assert get_resp_header(shown, "content-type") == ["image/webp"]
    assert {:ok, %{bytes: kept}} = RegentAgents.agent_picture(@wallet)
    assert shown.resp_body == kept
    assert {:ok, %{bytes: ^theirs}} = RegentAgents.agent_picture(@other)

    # Zeros would be refused as no picture once opened; too large comes first.
    {413, _headers, too_large} =
      assert_error_sent(413, fn ->
        send_picture.(%{picture: Base.encode64(:binary.copy(<<0>>, 65_536))})
      end)

    assert Jason.decode!(too_large)["error"]["code"] == "request_entity_too_large"

    assert error_code(send_picture.(%{picture: Base.encode64("<svg/>")})) == "not_a_picture"
    assert error_code(send_picture.(%{picture: "not base64!"})) == "invalid_picture"
    assert error_code(send_picture.(%{})) == "invalid_picture"
    assert {:ok, %{bytes: ^kept}} = RegentAgents.agent_picture(@wallet)

    # Four tries so far; the eleventh in the hour waits, whatever it holds.
    for _try <- 5..10, do: assert(send_picture.(%{}).status == 422)
    limited = send_picture.(%{picture: Base.encode64(png)})
    assert limited.status == 429
    assert error_code(limited) == "pictures_limited"
    assert [_seconds] = get_resp_header(limited, "retry-after")

    removed = signed(conn, :delete, "")
    assert Jason.decode!(removed.resp_body) == %{"removed" => true}
    assert {:ok, nil} = RegentAgents.agent_picture(@wallet)
    assert error_code(signed(conn, :delete, "")) == "picture_not_found"
    assert {:ok, %{bytes: ^theirs}} = RegentAgents.agent_picture(@other)

    {:ok, paired} = RegentAgents.get_my_agent(pairing_id, actor: person)
    assert :ok = RegentAgents.unpair_agent(paired, actor: person)
    Regents.RateLimiter.reset()
    assert send_picture.(%{picture: Base.encode64(png)}).status == 403
    assert {:ok, nil} = RegentAgents.agent_picture(@wallet)
  end

  defp signed(conn, method, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, "/api/agent/v1/picture", body)
  end

  defp error_code(conn), do: Jason.decode!(conn.resp_body)["error"]["code"]

  defp pair(conn, code) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/agents/v1/pair", Jason.encode!(%{code: code, name: "Sol", harness: "hermes"}))
  end

  # The sign-in service verifies every request as signed by the agent's key.
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

  defp person! do
    unique = Elixir.System.unique_integer([:positive])
    wallet = "0x" <> String.pad_leading(Integer.to_string(unique, 16), 40, "0")
    did = "did:privy:agent-picture:#{unique}"
    Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    %Person{privy_user_id: did}
  end
end
