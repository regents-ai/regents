defmodule AshPlatformWeb.OwnedClaimsControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  @alice "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @bob "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  import AshPlatform.NamesFixtures

  setup_all do
    ensure_claims_table!()
  end

  setup do
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    previous = Application.get_env(:ash_platform, :privy)
    Application.put_env(:ash_platform, :privy, app_id: "claims-fixture", verification_key: public)
    on_exit(fn -> Application.put_env(:ash_platform, :privy, previous || []) end)
    %{key: key}
  end

  test "fresh owner evidence returns recorded history without payment details", %{key: key} do
    insert_claim(9_007_199_254_740_993, String.upcase(@alice), %{
      ens_fqdn: "recorded.regent.eth",
      ens_tx_hash: "0x" <> String.duplicate("e", 64),
      ens_assigned_at: ~U[2025-01-02 03:04:05.123456Z],
      payment_tx_hash: "private-payment",
      price_wei: 50,
      formation_agent_slug: "private-agent"
    })

    conn = request(key, "alice", [@alice])
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert %{"claims" => [claim], "next" => nil} = json_response(conn, 200)
    assert claim["id"] == "9007199254740993"
    assert claim["ens_name"] == "recorded.regent.eth"
    assert claim["ens_assigned_at"] == "2025-01-02T03:04:05.123456Z"
    assert claim["ens_transaction"] == "0x" <> String.duplicate("e", 64)
    refute conn.resp_body =~ "private-payment"
    refute conn.resp_body =~ "price_wei"
    refute conn.resp_body =~ "private-agent"
    assert json_response(request(key, "bob", [@bob]), 200)["claims"] == []
    assert json_response(request(key, "no-wallet", []), 200)["claims"] == []
  end

  test "complete owner listing follows cursors and preserves nullable history", %{key: key} do
    for id <- 1..51, do: insert_claim(id, @alice)
    insert_claim(100, @bob)
    first = request(key, "alice", [@alice]) |> json_response(200)
    assert length(first["claims"]) == 50
    assert is_binary(first["next"])
    assert Enum.all?(first["claims"], &is_nil(&1["ens_assigned_at"]))
    second = request(key, "alice", [@alice], %{"after" => first["next"]}) |> json_response(200)
    assert Enum.map(second["claims"], & &1["id"]) == ["51"]
    assert second["next"] == nil
    # A cursor carries position, never another owner's authority.
    assert [%{"id" => "100"}] =
             json_response(request(key, "bob", [@bob], %{"after" => first["next"]}), 200)[
               "claims"
             ]
  end

  test "cookies, caller-selected wallets, swapped subjects and stale proof cannot authorize", %{
    key: key
  } do
    insert_claim(1, @alice)

    assert build_conn()
           |> init_test_session(%{wallet_address: @alice})
           |> get("/api/v1/claims")
           |> response(401)

    assert request(key, "bob", [@bob], %{"owner_address" => @alice}).status == 400
    assert request(key, "alice", [@alice], %{}, identity_subject: "bob").status == 401

    assert request(key, "alice", [@alice], %{}, expires: System.system_time(:second) - 60).status ==
             401

    assert request(key, "alice", [@alice], %{}, audience: "another-app").status == 401

    actor = %RegentPrivy.Session{
      app_id: "claims-fixture",
      privy_user_id: "alice",
      session_id: "s",
      wallet_addresses: [@alice],
      expires_at: 1
    }

    assert {:error, _} = AshPlatform.Names.list_my_claims(actor: actor)
    assert {:error, _} = AshPlatform.Names.list_my_claims(actor: %{wallet_addresses: [@alice]})
  end

  defp request(key, subject, wallets, params \\ %{}, opts \\ []) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => opts[:audience] || "claims-fixture",
      "sub" => subject,
      "iat" => now - 120,
      "exp" => opts[:expires] || now + 600
    }

    sign = fn claims ->
      {_, token} = key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()
      token
    end

    linked = Enum.map(wallets, &%{type: "wallet", chain_type: "ethereum", address: &1})

    identity =
      claims
      |> Map.put("sub", opts[:identity_subject] || subject)
      |> Map.put("linked_accounts", Jason.encode!(linked))

    build_conn()
    |> put_req_header(
      "authorization",
      "Bearer " <> sign.(Map.put(claims, "sid", "fixture-session"))
    )
    |> put_req_header("privy-id-token", sign.(identity))
    |> get("/api/v1/claims", params)
  end
end
