defmodule RegentsWeb.PublicNameTest do
  # A person's Public Display Name lives in the shared profile every Regent site
  # reads (`RegentIdentity.HTTP` at /api/v1/profile). It is read and changed for
  # the person signed in on this site, from its pages, or for the person an agent
  # they paired acts for (`RegentsWeb.Plugs.ProfileOwner`), and for nobody else.
  # A saved name shows at the next load on the Account page and in the account
  # menu (13 Nov 2026: a name saved on regents.sh was gone after a reload). People
  # sign in through the site's own sign-in step, with tokens signed as Privy signs
  # them; the sign-in service is stood in for and vouches for the agent's wallet.
  # Ported from ash-template's `AshTemplateWeb.PublicNameTest`.
  use RegentsWeb.ConnCase, async: false

  @did "did:privy:public-name"
  @wallet "0x" <> String.duplicate("d", 40)
  @agent "0x" <> String.duplicate("2", 40)
  @name "Ada Lovelace"

  setup do
    Regents.RateLimiter.reset()
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:regents, :privy)
    verifier = Application.fetch_env!(:regents, :privy_verifier)
    Application.put_env(:regents, :privy, Keyword.put(privy, :verification_key, pem))
    Application.put_env(:regents, :privy_verifier, RegentPrivy.Session)

    on_exit(fn ->
      Application.put_env(:regents, :privy, privy)
      Application.put_env(:regents, :privy_verifier, verifier)
      Regents.RateLimiter.reset()
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "walletAddress" => @agent,
          "agentBook" => nil,
          "agentRegistration" => nil,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => @agent,
            "chain_id" => 8453,
            "audience" => RegentAgents.Broker.audience()
          }
        }
      })
    end)

    %{key: key, app_id: privy[:app_id]}
  end

  test "the person signed in here reads and sets their name, a change only with the forms token, and it shows at the next load",
       %{key: key, app_id: app_id} do
    {signed_in, token, _menu} = sign_in(key, app_id, @did, @wallet)
    # Signing in gave the person their shared profile, with no name yet.
    assert read(signed_in)["display_name"] == nil

    # Without the forms token a change counts as signed out and changes nothing,
    # and the session the refused answer leaves still reads for the person, so
    # another site's page cannot sign them out either.
    refused = send_json(signed_in, %{display_name: "Mallory"}, nil)
    assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    assert read(refused)["display_name"] == nil

    saved = send_json(signed_in, %{display_name: @name}, token)
    assert json_response(saved, 200)["profile"]["display_name"] == @name
    assert read(signed_in)["display_name"] == @name

    page = signed_in |> recycle() |> get("/account") |> html_response(200)
    page = LazyHTML.from_document(page)

    assert page
           |> LazyHTML.query(~s(#account-profile input[name="display_name"]))
           |> LazyHTML.attribute("value") == [@name]

    assert page |> LazyHTML.query("#account-identity") |> LazyHTML.text() =~ @name
    assert page |> LazyHTML.query("#account-chip") |> LazyHTML.text() =~ @name

    # A later sign-in keeps the profile and its name.
    {_signed_in, _token, menu} = sign_in(key, app_id, @did, @wallet)
    assert menu["label"] == @name
  end

  test "with no sign-in nothing is read or changed" do
    for {method, body} <- [{:get, nil}, {:patch, Jason.encode!(%{display_name: "Mallory"})}] do
      refused =
        build_conn()
        |> init_test_session(%{"profile_id" => "forged"})
        |> put_private(:plug_skip_csrf_protection, false)
        |> put_req_header("content-type", "application/json")
        |> dispatch(@endpoint, method, "/api/v1/profile", body)

      assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    end
  end

  test "a signed-in session sent with an agent's header but no valid signature changes nothing",
       %{key: key, app_id: app_id} do
    {signed_in, token, _menu} = sign_in(key, app_id, @did, @wallet)

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

    # The agent's path never falls back to the person's cookie and forms token.
    forged =
      signed_in
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-csrf-token", token)
      |> put_req_header("x-siwa-signature", "forged")
      |> dispatch(@endpoint, :patch, "/api/v1/profile", Jason.encode!(%{display_name: "Mallory"}))

    assert forged.status == 401
    assert read(signed_in)["display_name"] == nil
  end

  test "a paired agent reads and sets its person's name, which reads back for that person and nobody else",
       %{key: key, app_id: app_id} do
    # An agent paired with no one acts for no one.
    assert json_response(agent(:get), 403)["error"]["code"] == "agent_not_paired"

    {person, _token, _menu} = sign_in(key, app_id, @did, @wallet)

    {someone_else, _token, _menu} =
      sign_in(key, app_id, "did:privy:someone-else", "0x" <> String.duplicate("e", 40))

    pair(@did)

    assert json_response(agent(:get), 200)["profile"]["display_name"] == nil

    saved = agent(:patch, %{display_name: "Named by my agent"})
    assert json_response(saved, 200)["profile"]["display_name"] == "Named by my agent"

    assert read(person)["display_name"] == "Named by my agent"
    assert read(someone_else)["display_name"] == nil
  end

  test "a paired agent whose person has not signed in here reads and changes nothing" do
    pair(@did)

    for {method, body} <- [{:get, nil}, {:patch, %{display_name: "Unsent"}}] do
      refused = agent(method, body)
      assert json_response(refused, 403)["error"]["code"] == "person_not_here"
    end
  end

  defp read(signed_in),
    do:
      signed_in
      |> recycle()
      |> get("/api/v1/profile")
      |> json_response(200)
      |> Map.fetch!("profile")

  # Phoenix's test connection skips the forms token check; these requests keep it,
  # as a browser's do.
  defp send_json(signed_in, body, token) do
    conn =
      signed_in
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")

    conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn
    dispatch(conn, @endpoint, :patch, "/api/v1/profile", Jason.encode!(body))
  end

  # The agent's request, signed with its wallet.
  defp agent(method, body \\ nil) do
    conn = put_req_header(build_conn(), "x-siwa-signature", "fixture-proof")

    conn =
      if body,
        do: put_req_header(conn, "content-type", "application/json"),
        else: conn

    dispatch(conn, @endpoint, method, "/api/v1/profile", body && Jason.encode!(body))
  end

  defp pair(privy_user_id) do
    code =
      RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: privy_user_id})

    RegentAgents.pair_agent!(code.code, "Fixture", :codex,
      actor: %RegentAgents.Agent{wallet: @agent}
    )
  end

  # The browser's steps: a fresh session, then Privy's two tokens on the sign-in
  # step, then the forms token the site's pages carry for the session that step
  # left. Answers the connection carrying that session, its forms token, and the
  # account menu the sign-in step answered with.
  defp sign_in(key, app_id, did, wallet) do
    csrf = build_conn() |> get("/auth/csrf")
    proof = proof(key, app_id, did, wallet)

    signed_in =
      csrf
      |> recycle()
      |> put_req_header("x-csrf-token", Jason.decode!(csrf.resp_body)["csrf_token"])
      |> put_req_header("authorization", "Bearer " <> proof.access)
      |> put_req_header("privy-id-token", proof.identity)
      |> post("/auth/privy/session")

    menu = json_response(signed_in, 200)["account_control"]
    page = signed_in |> recycle() |> get("/auth/csrf")
    {page, json_response(page, 200)["csrf_token"], menu}
  end

  defp proof(key, app_id, did, wallet) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => app_id,
      "sub" => did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => did
    }

    linked = [
      %{
        "type" => "wallet",
        "address" => wallet,
        "chain_type" => "ethereum",
        "wallet_client_type" => "metamask",
        "lv" => now - 1
      }
    ]

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!(linked)))
    }
  end
end
