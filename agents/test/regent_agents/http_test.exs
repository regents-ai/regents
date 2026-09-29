defmodule RegentAgents.HTTPTest do
  use RegentAgents.Case, async: true

  import Plug.Test

  @wallet "0x2222222222222222222222222222222222222222"

  defp send_request(method, path, body \\ nil) do
    conn =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    conn = RegentAgents.Test.Router.call(conn, RegentAgents.Test.Router.init([]))
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp put_req_header(conn, key, value), do: Plug.Conn.put_req_header(conn, key, value)

  # The SIWA service verifies the request and names the key that signed it.
  defp siwa_verifies(wallet \\ String.upcase(@wallet), audience \\ "test") do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        self(),
        {:verified, conn.request_path, Plug.Conn.get_req_header(conn, "x-siwa-audience"),
         Jason.decode!(body)}
      )

      Req.Test.json(conn, %{
        "code" => "http_envelope_valid",
        "data" => %{
          "verified" => true,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => "0x" <> String.slice(wallet, 2..-1//1),
            "chain_id" => 8453,
            "audience" => audience
          }
        }
      })
    end)
  end

  defp siwa_refuses(status, code) do
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{
        "error" => %{
          "code" => code,
          "message" => "This signed request was already used.",
          "hint" => "Sign a fresh request with a new nonce, then send it again."
        }
      })
    end)
  end

  test "an agent pairs with a code, signed for this site, and checks in on the pairing" do
    owner = person("sol")
    code = code!(owner)
    siwa_verifies()

    body = %{"code" => code, "name" => "Sol", "harness" => "codex"}
    assert {201, %{"data" => paired}} = send_request(:post, "/api/agents/v1/pair", body)
    assert %{"name" => "Sol", "harness" => "codex", "wallet" => @wallet} = paired

    assert_received {:verified, "/api/shared/siwa/http-verify", ["test"], envelope}
    assert %{"method" => "POST", "path" => "/api/agents/v1/pair", "body" => signed} = envelope
    assert Jason.decode!(signed) == body

    assert {200, %{"data" => checked_in}} = send_request(:get, "/api/agents/v1/me")
    assert checked_in["wallet"] == @wallet
    assert checked_in["account"] == %{"display_name" => "Person did:privy:sol"}

    assert_received {:verified, _path, _audience,
                     %{"method" => "GET", "path" => "/api/agents/v1/me"} = check_in}

    refute Map.has_key?(check_in, "body")
  end

  test "an unknown harness is named before anything is signed for" do
    body = %{"code" => code!(person("new")), "name" => "New", "harness" => "hal"}
    assert {400, %{"error" => error}} = send_request(:post, "/api/agents/v1/pair", body)
    assert error["code"] == "harness_unknown"
    assert error["hint"] =~ "claude_code"
    assert error["hint"] =~ "other"
    refute_received {:verified, _path, _audience, _envelope}
  end

  test "a missing field, an extra field or a used code cannot pair" do
    siwa_verifies()
    code = code!(person("used"))
    body = %{"code" => code, "name" => "Sol", "harness" => "muse"}

    assert {400, %{"error" => %{"code" => "pairing_failed"}}} =
             send_request(:post, "/api/agents/v1/pair", Map.delete(body, "name"))

    assert {400, %{"error" => %{"code" => "pairing_failed"}}} =
             send_request(:post, "/api/agents/v1/pair", Map.put(body, "extra", "x"))

    assert {201, _paired} = send_request(:post, "/api/agents/v1/pair", body)

    assert {400, %{"error" => %{"code" => "pairing_failed", "hint" => _hint}}} =
             send_request(:post, "/api/agents/v1/pair", body)
  end

  test "an agent nobody paired is told to ask for a code" do
    siwa_verifies()

    assert {404, %{"error" => %{"code" => "not_paired"}}} =
             send_request(:get, "/api/agents/v1/me")

    assert {404, %{"error" => %{"code" => "not_paired"}}} =
             send_request(:get, "/api/agents/v1/me?x=1")
  end

  test "the SIWA service's refusal reaches the agent as the SIWA service wrote it" do
    siwa_refuses(409, "request_replayed")

    assert {409,
            %{
              "error" => %{
                "code" => "request_replayed",
                "message" => "This signed request was already used.",
                "hint" => "Sign a fresh request with a new nonce, then send it again."
              }
            }} = send_request(:get, "/api/agents/v1/me")
  end

  test "a key verified for another site, or no answer from the SIWA service, pairs nothing" do
    siwa_verifies(@wallet, "patchbay")

    assert {401, %{"error" => %{"code" => "verification_failed"}}} =
             send_request(:get, "/api/agents/v1/me")

    Req.Test.stub(RegentAgents.Broker, &Req.Test.transport_error(&1, :econnrefused))

    assert {503, %{"error" => %{"code" => "verification_unavailable"}}} =
             send_request(:get, "/api/agents/v1/me")
  end

  test "any other request under the mount is not an agent request" do
    assert {404, %{"error" => %{"code" => "not_found"}}} =
             send_request(:get, "/api/agents/v1/pair")
  end
end
