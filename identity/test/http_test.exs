defmodule RegentIdentity.HTTPTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentIdentity.TestRepo)
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, key} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()

    Application.put_env(:identity_http_fixture, :privy,
      app_id: "shared-app",
      verification_key: key
    )

    on_exit(fn -> Application.delete_env(:identity_http_fixture, :privy) end)
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "shared-app",
      "sub" => "http-#{System.unique_integer([:positive])}",
      "iat" => now - 1,
      "exp" => now + 600
    }

    access = sign(Map.put(claims, "sid", "session"), jwk)

    identity =
      sign(
        Map.put(
          claims,
          "linked_accounts",
          Jason.encode!([
            %{"type" => "twitter_oauth", "subject" => claims["sub"], "username" => "verified_x"},
            %{
              "type" => "wallet",
              "chain_type" => "ethereum",
              "address" => "0x1111111111111111111111111111111111111111"
            }
          ])
        ),
        jwk
      )

    %{access: access, identity: identity}
  end

  defp sign(claims, key) do
    {_, token} = key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp request(method, path, tokens, body \\ nil) do
    conn(method, path, if(body, do: Jason.encode!(body), else: nil))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{tokens.access}")
    |> put_req_header("privy-id-token", tokens.identity)
    |> RegentIdentity.HTTP.call(:identity_http_fixture)
  end

  test "signed HTTP proof reaches the same private profile contract", tokens do
    assert request(:get, "/", tokens).status == 404
    synced = request(:post, "/sync", tokens)
    assert synced.status == 200
    assert get_resp_header(synced, "cache-control") == ["no-store"]
    profile = Jason.decode!(synced.resp_body)["profile"]
    assert profile["x"]["verified"] == true
    refute Map.has_key?(profile, "privy_user_id")
    refute Map.has_key?(profile["x"], "subject")
    assert Jason.decode!(request(:get, "/", tokens).resp_body)["profile"] == profile
    edited = request(:patch, "/", tokens, %{display_name: "My name"})
    assert edited.status == 200
    assert Jason.decode!(edited.resp_body)["profile"]["display_name"] == "My name"
    assert request(:patch, "/", tokens, %{x_subject: "fake"}).status == 422
    assert request(:patch, "/", tokens, %{profile_id: "other"}).status == 422
  end

  test "missing or swapped proof never creates a profile", tokens do
    assert conn(:get, "/")
           |> RegentIdentity.HTTP.call(:identity_http_fixture)
           |> Map.fetch!(:status) == 401

    assert request(:post, "/sync", %{access: tokens.identity, identity: tokens.access}).status ==
             401

    assert request(:get, "/", tokens).status == 404
  end

  test "a browser's captured subject only restricts signed authority", tokens do
    response =
      conn(:post, "/sync")
      |> put_req_header("authorization", "Bearer #{tokens.access}")
      |> put_req_header("privy-id-token", tokens.identity)
      |> put_req_header("x-privy-user-id", "another-subject")
      |> RegentIdentity.HTTP.call(:identity_http_fixture)

    assert response.status == 401
    assert request(:get, "/", tokens).status == 404
  end

  test "an edit from a previously displayed account cannot change the new account", tokens do
    assert request(:post, "/sync", tokens).status == 200

    response =
      conn(:patch, "/", Jason.encode!(%{display_name: "Wrong account's draft"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{tokens.access}")
      |> put_req_header("privy-id-token", tokens.identity)
      |> put_req_header("x-regent-profile-id", Ash.UUID.generate())
      |> RegentIdentity.HTTP.call(:identity_http_fixture)

    assert response.status == 422
    assert Jason.decode!(request(:get, "/", tokens).resp_body)["profile"]["display_name"] == nil
  end

  test "an upstream form parser cannot turn a form into an authenticated JSON edit", tokens do
    assert request(:post, "/sync", tokens).status == 200

    response =
      conn(:patch, "/", "display_name=Forged")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("authorization", "Bearer #{tokens.access}")
      |> put_req_header("privy-id-token", tokens.identity)
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:urlencoded]))
      |> RegentIdentity.HTTP.call(:identity_http_fixture)

    assert response.status == 415
    assert Jason.decode!(request(:get, "/", tokens).resp_body)["profile"]["display_name"] == nil
  end
end
