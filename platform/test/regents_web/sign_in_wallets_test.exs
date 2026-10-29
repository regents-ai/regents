defmodule RegentsWeb.SignInWalletsTest do
  # Sean, 20 Oct 2026: the Wallets tab of Account shows "User wallet" only when the person
  # signed in to Privy with a wallet of their own, and the wallet Privy made for
  # everyone as the "Regents embedded wallet". An outside wallet must never show
  # as the Regents wallet. Sean, 21 Oct 2026 (9. a): the person's own wallet is
  # their main wallet, even though Privy makes the Regents wallet during the
  # sign-in. This signs in through the site's own sign-in step, as the browser
  # does, with tokens signed as Privy signs them.
  use RegentsWeb.ConnCase, async: false

  @own "0x" <> String.duplicate("e", 40)
  @made "0x" <> String.duplicate("7", 40)

  setup %{conn: conn} do
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:regents, :privy)
    verifier = Application.fetch_env!(:regents, :privy_verifier)

    Application.put_env(
      :regents,
      :privy,
      privy |> Keyword.put(:app_id, "test-app") |> Keyword.put(:verification_key, pem)
    )

    Application.put_env(:regents, :privy_verifier, RegentPrivy.Session)

    on_exit(fn ->
      Application.put_env(:regents, :privy, privy)
      Application.put_env(:regents, :privy_verifier, verifier)
    end)

    %{key: key, conn: conn}
  end

  test "a wallet sign-in shows the person's own wallet and their Regents wallet", %{
    conn: conn,
    key: key
  } do
    html =
      conn
      |> sign_in(key, "did:privy:own-wallet", [
        wallet(@own, 2_000, "metamask"),
        wallet(@made, 2_001, "privy")
      ])
      |> get("/account/wallets")
      |> html_response(200)

    assert section(html, "User wallet") =~ @own
    assert section(html, "Regents embedded wallet") =~ @made
    refute section(html, "Regents embedded wallet") =~ @own
  end

  test "the person's own wallet stays their main wallet after Privy makes the Regents wallet",
       %{conn: conn, key: key} do
    sign_in(conn, key, "did:privy:main-wallet", [wallet(@own, 4_000, "metamask")])

    sign_in(conn, key, "did:privy:main-wallet", [
      wallet(@own, 4_000, "metamask"),
      wallet(@made, 4_001, "privy")
    ])

    {:ok, account} =
      Regents.Accounts.get_by_privy_did("did:privy:main-wallet", actor: %Regents.Actors.System{})

    assert account.wallet_address == @own
    assert Enum.sort(account.wallet_addresses) == Enum.sort([@own, @made])
  end

  test "an email sign-in shows only the Regents wallet", %{conn: conn, key: key} do
    email = %{"type" => "email", "address" => "made@example.com", "lv" => 1_000}

    html =
      conn
      |> sign_in(key, "did:privy:email-only", [email, wallet(@made, 1_001, "privy")])
      |> get("/account/wallets")
      |> html_response(200)

    refute html =~ "User wallet"
    assert section(html, "Regents embedded wallet") =~ @made
  end

  test "a wallet sign-in before Privy made the Regents wallet says it is still to come", %{
    conn: conn,
    key: key
  } do
    html =
      conn
      |> sign_in(key, "did:privy:not-made-yet", [wallet(@own, 3_000, "metamask")])
      |> get("/account/wallets")
      |> html_response(200)

    assert section(html, "User wallet") =~ @own
    assert section(html, "Regents embedded wallet") =~ "Made for you at your next sign-in"
    refute section(html, "Regents embedded wallet") =~ @own
  end

  # The browser's steps: a fresh session, then Privy's two tokens on the sign-in
  # step, then the page with the cookie that step left.
  defp sign_in(conn, key, did, linked_accounts) do
    csrf = get(conn, "/auth/csrf")
    token = Jason.decode!(csrf.resp_body)["csrf_token"]
    proof = proof(key, did, linked_accounts)

    signed_in =
      csrf
      |> recycle()
      |> put_req_header("x-csrf-token", token)
      |> put_req_header("authorization", "Bearer " <> proof.access)
      |> put_req_header("privy-id-token", proof.identity)
      |> post("/auth/privy/session")

    assert signed_in.status == 200
    recycle(signed_in)
  end

  # The words after a label, up to the next label.
  defp section(html, label) do
    [_before, rest] = String.split(html, "<dt>#{label}</dt>", parts: 2)
    rest |> String.split("<dt>", parts: 2) |> hd()
  end

  defp wallet(address, verified_at, client),
    do: %{
      "type" => "wallet",
      "address" => address,
      "chain_type" => "ethereum",
      "wallet_client_type" => client,
      "lv" => verified_at
    }

  defp proof(key, did, linked_accounts) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => did
    }

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!(linked_accounts)))
    }
  end
end
