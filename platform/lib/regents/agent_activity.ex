defmodule Regents.AgentActivity do
  @moduledoc """
  What a paired agent has done across the Regents sites since it was paired,
  in plain words. The sign-in service keeps the record: every request an
  agent signs is verified there, whichever site it went to.
  """

  alias RegentAgents.PairedAgent

  @sites %{
    "regents" => "Regents Labs",
    "autolaunch" => "Autolaunch",
    "techtree" => "Techtree",
    "patchbay" => "Patchbay",
    "keyfleet" => "KeyFleet"
  }

  @type entry :: %{site: String.t(), action: String.t(), occurred_at: DateTime.t()}

  @spec recent(PairedAgent.t()) :: {:ok, [entry()]} | {:error, term()}
  def recent(%PairedAgent{} = agent) do
    with {:ok, config} <- config(),
         {:ok, %Req.Response{status: 200, body: %{"data" => %{"activity" => activity}}}} <-
           Req.post(
             config.base_url <> "/api/shared/siwa/activity",
             request_options(config, agent)
           ) do
      {:ok, Enum.flat_map(activity, &describe/1) ++ [paired(agent)]}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # The pairing itself is the agent's own record here; the request that made
  # it was verified a moment before the agent existed.
  defp paired(agent),
    do: %{site: "Regents Labs", action: "Paired with your account", occurred_at: agent.paired_at}

  # Requests to sites outside the Regents family, and the pairing request
  # already shown by the pairing itself, are left out.
  defp describe(%{
         "audience" => audience,
         "method" => method,
         "path" => path,
         "occurred_at" => at
       }) do
    with {:ok, site} <- Map.fetch(@sites, audience),
         {:ok, action} <- action(audience, method, path),
         {:ok, occurred_at, _offset} <- DateTime.from_iso8601(at) do
      [%{site: site, action: action, occurred_at: occurred_at}]
    else
      _other -> []
    end
  end

  defp action(_audience, "GET", "/api/agents/v1/me"), do: {:ok, "Checked in"}
  defp action(_audience, "POST", "/api/agents/v1/pair"), do: :skip

  defp action(_audience, method, _path) when method in ["GET", "HEAD"],
    do: {:ok, "Looked something up"}

  defp action(_audience, _method, _path), do: {:ok, "Asked to make a change"}

  defp config do
    config = Application.fetch_env!(:regents, :siwa)

    case {config[:base_url], config[:activity_read_token]} do
      {"https://" <> _rest = base_url, token} when is_binary(token) and token != "" ->
        {:ok, %{base_url: String.trim_trailing(base_url, "/"), token: token}}

      _missing ->
        {:error, :not_configured}
    end
  end

  defp request_options(config, agent) do
    [retry: false, receive_timeout: 5_000, connect_options: [timeout: 2_000]]
    |> Keyword.merge(Application.get_env(:regents, :siwa_req_options, []))
    |> Keyword.merge(
      auth: {:bearer, config.token},
      json: %{wallet_address: agent.wallet, since: DateTime.to_iso8601(agent.paired_at)}
    )
  end
end
