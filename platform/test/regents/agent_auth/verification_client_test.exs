defmodule Regents.AgentAuth.VerificationClientTest do
  use ExUnit.Case, async: false

  alias Regents.AgentAuth.{SiwaHttpVerificationClient, VerificationClient}

  @wallet "0x2222222222222222222222222222222222222222"

  setup do
    previous_client = Application.fetch_env!(:regents, :agent_verification_client)
    previous_siwa = Application.fetch_env!(:regents, :siwa)
    previous_req_options = Application.get_env(:regents, :siwa_req_options)

    Application.put_env(
      :regents,
      :agent_verification_client,
      Regents.AgentAuth.DeterministicVerificationClient
    )

    Application.put_env(:regents, :siwa,
      base_url: "https://siwa.example.test",
      audience: "regents-test"
    )

    Application.put_env(:regents, :siwa_req_options, plug: {Req.Test, __MODULE__})
    Process.delete(:agent_verification_result)
    Process.delete(:capture_agent_verification_calls)

    on_exit(fn ->
      Application.put_env(:regents, :agent_verification_client, previous_client)
      Application.put_env(:regents, :siwa, previous_siwa)
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
      assert Plug.Conn.get_req_header(conn, "x-siwa-audience") == ["regents-test"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "method" => "POST",
               "path" => "/api/agents/v1/pair",
               "headers" => %{"signature" => "sig", "x-key-id" => "agent-key"},
               "body" => ~s({"code":"temporary-code"})
             }

      Req.Test.json(conn, verified_body(String.upcase(@wallet)))
    end)

    assert {:ok, identity} = SiwaHttpVerificationClient.verify(envelope())
    assert identity == identity()
  end

  test "rejections, malformed responses, and a wallet for another chain or site fail closed" do
    for {status, body, expected} <- [
          {401, %{"code" => "http_envelope_invalid"}, :verification_failed},
          {500, %{"error" => "unavailable"}, :verification_failed},
          {200, %{"data" => %{"verified" => true}}, :invalid_verification_response},
          {200, verified_body(@wallet, 1), :invalid_verification_response},
          {200, verified_body(@wallet, 8453, "patchbay"), :invalid_verification_response}
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
          [base_url: nil, audience: "regents-test"],
          [base_url: "http://siwa.example.test", audience: "regents-test"],
          [base_url: "https://siwa.example.test", audience: nil]
        ] do
      Application.put_env(:regents, :siwa, config)
      assert SiwaHttpVerificationClient.verify(envelope()) == {:error, :not_configured}
    end
  end

  defp envelope do
    %{
      method: "POST",
      path: "/api/agents/v1/pair",
      headers: %{"signature" => "sig", "x-key-id" => "agent-key"},
      body: ~s({"code":"temporary-code"})
    }
  end

  defp identity, do: %{wallet: @wallet}

  defp verified_body(wallet, chain_id \\ 8453, audience \\ "regents-test") do
    %{
      "code" => "http_envelope_valid",
      "data" => %{
        "verified" => true,
        "principal" => %{
          "kind" => "wallet",
          "wallet_address" => wallet,
          "chain_id" => chain_id,
          "audience" => audience
        }
      }
    }
  end

  defp restore(key, nil), do: Application.delete_env(:regents, key)
  defp restore(key, value), do: Application.put_env(:regents, key, value)
end
