defmodule RegentsWeb.PublicNameTest do
  # A person's Public Display Name lives in the shared profile every Regent site
  # reads. Saved with the sign-in's own proof, as the Account page's browser code
  # saves it, it shows at the next load on the Account page and in the account
  # menu, and a later sign-in answers with it (13 Nov 2026: a name saved on
  # regents.sh was gone after a reload). Tokens are signed as Privy signs them.
  # Ported from ash-template's `AshTemplateWeb.PublicNameTest`.
  use RegentsWeb.ConnCase, async: false

  @did "did:privy:public-name"
  @wallet "0x" <> String.duplicate("d", 40)
  @name "Ada Lovelace"

  setup %{conn: conn} do
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:regents, :privy)
    verifier = Application.fetch_env!(:regents, :privy_verifier)
    Application.put_env(:regents, :privy, Keyword.put(privy, :verification_key, pem))
    Application.put_env(:regents, :privy_verifier, RegentPrivy.Session)

    on_exit(fn ->
      Application.put_env(:regents, :privy, privy)
      Application.put_env(:regents, :privy_verifier, verifier)
    end)

    %{conn: conn, proof: proof(key, privy[:app_id])}
  end

  test "a saved name shows on the Account page and in the account menu at the next load", %{
    conn: conn,
    proof: proof
  } do
    {signed_in, _menu} = sign_in(conn, proof)
    assert profile(:post, "/api/v1/profile/sync", proof).status == 200
    assert profile(:patch, "/api/v1/profile", proof, %{display_name: @name}).status == 200

    page = signed_in |> get("/account") |> html_response(200) |> LazyHTML.from_document()

    assert page
           |> LazyHTML.query(~s(#account-profile input[name="display_name"]))
           |> LazyHTML.attribute("value") == [@name]

    assert page |> LazyHTML.query("#account-identity") |> LazyHTML.text() =~ @name
    assert page |> LazyHTML.query("#account-chip") |> LazyHTML.text() =~ @name

    {_signed_in, menu} = sign_in(build_conn(), proof)
    assert menu["label"] == @name
  end

  # The browser's steps: a fresh session, then Privy's two tokens on the sign-in
  # step. Answers the connection carrying the cookie that step left, and the
  # account menu the step answered with.
  defp sign_in(conn, proof) do
    csrf = get(conn, "/auth/csrf")
    token = Jason.decode!(csrf.resp_body)["csrf_token"]

    signed_in =
      csrf
      |> recycle()
      |> put_req_header("x-csrf-token", token)
      |> put_req_header("authorization", "Bearer " <> proof.access)
      |> put_req_header("privy-id-token", proof.identity)
      |> post("/auth/privy/session")

    {recycle(signed_in), json_response(signed_in, 200)["account_control"]}
  end

  defp profile(method, path, proof, body \\ nil) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> proof.access)
    |> put_req_header("privy-id-token", proof.identity)
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, body && Jason.encode!(body))
  end

  defp proof(key, app_id) do
    now = System.system_time(:second)

    wallet = %{
      "type" => "wallet",
      "address" => @wallet,
      "chain_type" => "ethereum",
      "wallet_client_type" => "metamask",
      "lv" => now - 1
    }

    claims = %{
      "iss" => "privy.io",
      "aud" => app_id,
      "sub" => @did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => "public-name"
    }

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!([wallet])))
    }
  end
end
