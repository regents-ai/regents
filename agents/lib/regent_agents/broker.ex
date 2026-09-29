defmodule RegentAgents.Broker do
  @moduledoc """
  Sends a signed agent request to the SIWA service to be verified, for this
  site's audience, from `config :regent_agents, siwa: [url: ..., audience: ...]`.
  """
  @behaviour Siwa.AgentAuthPlug.Client

  @impl true
  def verify_http_request(payload, audience: audience) do
    Siwa.AgentAuthPlug.BrokerClient.verify_http_request(payload,
      http: __MODULE__,
      base_url: Keyword.fetch!(config(), :url),
      audience: audience,
      connect_timeout_ms: 2_000,
      receive_timeout_ms: 5_000
    )
  end

  @doc "This site's SIWA audience."
  @spec audience() :: String.t()
  def audience, do: Keyword.fetch!(config(), :audience)

  # Verification spends replay state. Never retry or follow a redirect.
  @doc false
  def request(options) do
    options
    |> Keyword.merge(retry: false, redirect: false)
    |> Keyword.merge(Application.get_env(:regent_agents, :req_options, []))
    |> Req.request()
  end

  defp config, do: Application.fetch_env!(:regent_agents, :siwa)
end
