defmodule AshPlatform.AgentAuth.SiwaHttpVerificationClient do
  @moduledoc false
  @behaviour AshPlatform.AgentAuth.VerificationClient

  @base_chain_id 8453

  @impl true
  def verify(envelope) do
    with {:ok, config} <- config(),
         {:ok, response} <-
           Req.post(
             config.base_url <> "/api/shared/siwa/http-verify",
             request_options(config,
               headers: [{"x-siwa-audience", config.audience}],
               json: wire_envelope(envelope)
             )
           ) do
      case response.status do
        200 -> normalize_verified_identity(response.body)
        _status -> {:error, :verification_failed}
      end
    else
      {:error, %Req.TransportError{}} -> {:error, :verification_unavailable}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _reason} -> {:error, :verification_unavailable}
    end
  end

  defp config do
    config = Application.fetch_env!(:ash_platform, :siwa)
    base_url = config[:base_url]
    audience = config[:audience]

    if valid_base_url?(base_url) and present?(audience) do
      {:ok, %{base_url: String.trim_trailing(base_url, "/"), audience: audience}}
    else
      {:error, :not_configured}
    end
  end

  defp request_options(_config, options) do
    [retry: false, receive_timeout: 5_000, connect_options: [timeout: 2_000]]
    |> Keyword.merge(Application.get_env(:ash_platform, :siwa_req_options, []))
    |> Keyword.merge(options)
  end

  defp wire_envelope(envelope) do
    %{
      method: envelope.method,
      path: envelope.path,
      headers: envelope.headers,
      body: envelope.body
    }
  end

  defp normalize_verified_identity(%{
         "code" => "http_envelope_valid",
         "data" => %{
           "verified" => true,
           "chainId" => @base_chain_id,
           "agent_claims" => %{
             "agent_id" => agent_id,
             "registry_address" => registry_address,
             "token_id" => token_id,
             "wallet_address" => wallet,
             "chain_id" => @base_chain_id
           }
         }
       }) do
    with true <- present?(agent_id),
         true <- present?(token_id),
         {:ok, registry_address} <- normalize_address(registry_address),
         {:ok, wallet} <- normalize_address(wallet) do
      {:ok,
       %{
         agent_id: agent_id,
         registry_address: registry_address,
         token_id: token_id,
         wallet: wallet
       }}
    else
      _ -> {:error, :invalid_verification_response}
    end
  end

  defp normalize_verified_identity(_body), do: {:error, :invalid_verification_response}

  defp normalize_address(value) when is_binary(value) do
    normalized = String.downcase(value)

    if Regex.match?(~r/\A0x[0-9a-f]{40}\z/, normalized),
      do: {:ok, normalized},
      else: {:error, :invalid_address}
  end

  defp normalize_address(_value), do: {:error, :invalid_address}

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp valid_base_url?(value) do
    case URI.parse(value || "") do
      %URI{scheme: "https", host: host} when is_binary(host) -> host != ""
      _uri -> false
    end
  end
end
