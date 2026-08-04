defmodule AshPlatform.AgentAuth.VerificationClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.AgentAuth.{SiwaHttpVerificationClient, VerificationClient}

  @registry "0x1111111111111111111111111111111111111111"
  @wallet "0x2222222222222222222222222222222222222222"

  setup do
    previous_client = Application.fetch_env!(:ash_platform, :agent_verification_client)
    previous_siwa = Application.fetch_env!(:ash_platform, :siwa)
    previous_req_options = Application.get_env(:ash_platform, :siwa_req_options)

    Application.put_env(
      :ash_platform,
      :agent_verification_client,
      AshPlatform.AgentAuth.DeterministicVerificationClient
    )

    Application.put_env(:ash_platform, :siwa,
      base_url: "https://siwa.example.test",
      audience: "ash-platform-test"
    )

    Application.put_env(:ash_platform, :siwa_req_options, plug: {Req.Test, __MODULE__})
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)

    on_exit(fn ->
      Application.put_env(:ash_platform, :agent_verification_client, previous_client)
      Application.put_env(:ash_platform, :siwa, previous_siwa)
      restore(:siwa_req_options, previous_req_options)
    end)

    :ok
  end

  test "the injected deterministic verifier implements the verification contract" do
    envelope = envelope()
    identity = identity()
    Process.put(:capture_agent_verification_calls, true)
    Process.put(:agent_verification_result, {:ok, identity})

    assert VerificationClient.verify(envelope) == {:ok, identity}
    assert_received {:agent_verification, ^envelope}

    Process.delete(:agent_verification_result)
    assert VerificationClient.verify(envelope) == {:error, :verification_failed}
  end

  test "the HTTP verifier sends the canonical envelope and normalizes verified identity" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/shared/siwa/http-verify"
      assert Plug.Conn.get_req_header(conn, "x-siwa-audience") == ["ash-platform-test"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "method" => "POST",
               "path" => "/api/formation/v1/regents/regent-id/agent-links/claim",
               "headers" => %{"signature" => "sig", "x-key-id" => "agent-key"},
               "body" => "temporary-code"
             }

      Req.Test.json(conn, verified_body(String.upcase(@registry), String.upcase(@wallet)))
    end)

    assert {:ok, identity} = SiwaHttpVerificationClient.verify(envelope())
    assert identity == identity()
  end

  test "rejections, malformed responses, and unexpected chain identity fail closed" do
    for {status, body, expected} <- [
          {401, %{"code" => "http_envelope_invalid"}, :verification_failed},
          {500, %{"error" => "unavailable"}, :verification_failed},
          {200, %{"data" => %{"verified" => true}}, :invalid_verification_response},
          {200, verified_body(@registry, @wallet, 1), :invalid_verification_response}
        ] do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
      end)

      assert SiwaHttpVerificationClient.verify(envelope()) == {:error, expected}
    end
  end

  test "transport failure is bounded, normalized, and never retried" do
    test_process = self()

    Req.Test.expect(__MODULE__, 1, fn conn ->
      send(test_process, :verification_attempt)
      Req.Test.transport_error(conn, :timeout)
    end)

    assert SiwaHttpVerificationClient.verify(envelope()) ==
             {:error, :verification_unavailable}

    assert_received :verification_attempt
    refute_received :verification_attempt
  end

  test "missing or insecure configuration fails before making a request" do
    for config <- [
          [base_url: nil, audience: "ash-platform-test"],
          [base_url: "http://siwa.example.test", audience: "ash-platform-test"],
          [base_url: "https://siwa.example.test", audience: nil]
        ] do
      Application.put_env(:ash_platform, :siwa, config)
      assert SiwaHttpVerificationClient.verify(envelope()) == {:error, :not_configured}
    end
  end

  defp envelope do
    %{
      method: "POST",
      path: "/api/formation/v1/regents/regent-id/agent-links/claim",
      headers: %{"signature" => "sig", "x-key-id" => "agent-key"},
      body: "temporary-code"
    }
  end

  defp identity do
    %{
      agent_id: "eip155:8453:erc8004:#{@registry}:7",
      registry_address: @registry,
      token_id: "7",
      wallet: @wallet
    }
  end

  defp verified_body(registry, wallet, chain_id \\ 8453) do
    %{
      "code" => "http_envelope_valid",
      "data" => %{
        "verified" => true,
        "chainId" => chain_id,
        "agent_claims" => %{
          "agent_id" => "eip155:8453:erc8004:#{@registry}:7",
          "registry_address" => registry,
          "token_id" => "7",
          "wallet_address" => wallet,
          "chain_id" => chain_id
        }
      }
    }
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
