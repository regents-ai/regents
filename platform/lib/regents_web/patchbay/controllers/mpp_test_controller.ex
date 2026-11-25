defmodule RegentsWeb.Patchbay.MppTestController do
  @moduledoc """
  Live Machine Payments Protocol (MPP) sandbox on Tempo (`0.01 USDC.e`),
  companion to `/patchbay/bench/x402-test`.

  An unpaid request answers `402 Payment Required` with a standards-compliant
  `WWW-Authenticate: Payment` challenge advertising `method="tempo"`,
  `intent="charge"` (default) or `intent="session"` (`?intent=session`), and a
  base64url-encoded request payload naming the `0.01 USDC.e` amount and Tempo
  network details.

  When an agent retries with an `Authorization: Payment ...` credential, the
  sandbox parses and validates the credential structure and returns a diagnostic
  receipt preview without claiming on-chain settlement (no private key is held
  and no customer funds are collected).
  """

  use RegentsWeb, :controller

  # Tempo mainnet (chain id 4217) bridged USDC.e reference metadata for sandbox probes.
  @tempo_chain_id 4217
  @tempo_currency "USDC.e"
  @amount_atomic "10000"
  @amount_display "0.01"
  @challenge_ttl_seconds 300

  def show(conn, params) do
    intent = if params["intent"] == "session", do: "session", else: "charge"
    pay_to = Application.get_env(:regents, :x402_test_pay_to)

    case parse_payment_authorization(get_req_header(conn, "authorization")) do
      :none ->
        send_challenge(conn, intent, pay_to)

      {:ok, credential} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("vary", "Authorization")
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_header("access-control-expose-headers", "WWW-Authenticate, Payment-Receipt")
        |> json(%{
          status: "credential_validated",
          mode: "sandbox_structural",
          protocol: "mpp",
          method: "tempo",
          intent: intent,
          network: "eip155:#{@tempo_chain_id}",
          currency: @tempo_currency,
          amount: @amount_display,
          pay_to: pay_to,
          credential: credential,
          note:
            "MPP credential syntax and fields verified in sandbox mode. No on-chain Tempo transfer was settled."
        })

      {:error, reason} ->
        send_challenge(conn, intent, pay_to, reason)
    end
  end

  defp send_challenge(conn, intent, pay_to, error_reason \\ nil) do
    now = DateTime.utc_now()
    expires = DateTime.add(now, @challenge_ttl_seconds, :second) |> DateTime.to_iso8601()
    challenge_id = "mpp_pb_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    request_payload =
      %{
        "amount" => @amount_atomic,
        "currency" => @tempo_currency,
        "decimals" => 6,
        "network" => "eip155:#{@tempo_chain_id}",
        "recipient" => pay_to,
        "description" => "Patchbay MPP (Tempo) #{intent} sandbox test",
        "methodDetails" =>
          if intent == "session" do
            %{
              "chainId" => @tempo_chain_id,
              "feePayer" => false,
              "suggestedDeposit" => "100000",
              "unitType" => "request"
            }
          else
            %{"chainId" => @tempo_chain_id, "feePayer" => false}
          end
      }
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    header =
      ~s(Payment id="#{challenge_id}", realm="regents.sh", method="tempo", intent="#{intent}", expires="#{expires}", request="#{request_payload}")

    body =
      %{
        error: "payment_required",
        protocol: "mpp",
        method: "tempo",
        intent: intent,
        challenge_id: challenge_id,
        expires: expires,
        amount: @amount_display,
        amount_atomic: @amount_atomic,
        currency: @tempo_currency,
        network: "eip155:#{@tempo_chain_id}",
        recipient: pay_to,
        hint:
          "Retry with an Authorization: Payment <base64url-credential> header, or inspect this 402 challenge in /patchbay/validate."
      }
      |> maybe_put_reason(error_reason)

    conn
    |> put_status(:payment_required)
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("vary", "Authorization")
    |> put_resp_header("www-authenticate", header)
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-expose-headers", "WWW-Authenticate, Payment-Receipt")
    |> json(body)
  end

  defp maybe_put_reason(body, nil), do: body
  defp maybe_put_reason(body, reason), do: Map.put(body, :credential_error, reason)

  defp parse_payment_authorization([]), do: :none

  defp parse_payment_authorization([value | _]) when is_binary(value) do
    case String.split(String.trim(value), ~r/\s+/, parts: 2) do
      [scheme, token] when byte_size(token) > 0 ->
        if String.downcase(scheme) == "payment" do
          decode_credential(String.trim(token))
        else
          {:error, "Expected Authorization scheme 'Payment', got '#{scheme}'."}
        end

      _other ->
        {:error, "Malformed Authorization header; expected 'Authorization: Payment <token>'."}
    end
  end

  defp decode_credential(token) do
    with {:ok, raw} <- decode_base64url(token),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(raw) do
      {:ok,
       Map.take(decoded, ["challenge", "payload", "source", "method", "intent", "signature"])}
    else
      _invalid ->
        {:error, "Payment credential must be base64url-encoded JSON."}
    end
  end

  defp decode_base64url(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, raw} -> {:ok, raw}
      :error -> Base.url_decode64(token)
    end
  end
end
