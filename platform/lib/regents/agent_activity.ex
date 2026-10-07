defmodule Regents.AgentActivity do
  @moduledoc """
  What a paired agent has done across the Regents sites since it was paired,
  in plain words and 20 requests at a time, newest first, its listing in the
  agent registry, if it has one, and
  whether a person verified with World ID stands behind it, with how many agents
  that person stands behind. The sign-in service keeps all three: every request
  an agent signs is verified there, whichever site it went to, an agent lists
  itself through it, and it reads World's record of the person. Only whether
  there is such a person, and their agent count, is kept here
  (`RegentAgents.HumanBacking`).
  """

  alias RegentAgents.{HumanBacking, PairedAgent}

  @sites %{
    "regents" => "Regents Labs",
    "autolaunch" => "Autolaunch",
    "techtree" => "Techtree",
    "patchbay" => "Patchbay",
    "keyfleet" => "KeyFleet"
  }

  @type entry :: %{site: String.t(), action: String.t(), occurred_at: DateTime.t()}
  @type listing :: %{url: String.t(), number: String.t()}

  @type page :: %{
          entries: [entry()],
          next: String.t() | nil,
          listing: listing() | nil,
          human_backing: HumanBacking.t()
        }

  @doc """
  The newest page of the agent's activity, or with `after_cursor` set to an earlier
  page's `next`, the page after it. `next` is nil on the last page, which ends
  with the pairing itself.
  """
  @spec recent(PairedAgent.t(), String.t() | nil) :: {:ok, page()} | {:error, term()}
  def recent(%PairedAgent{} = agent, after_cursor \\ nil) do
    with {:ok, config} <- config(),
         {:ok,
          %Req.Response{
            status: 200,
            body: %{
              "data" => %{
                "activity" => activity,
                "next" => next,
                "agentRegistration" => registration,
                "agentBook" => book
              }
            }
          }}
         when is_nil(next) or (is_binary(next) and next != "") <-
           Req.post(
             config.base_url <> "/api/shared/siwa/activity",
             request_options(config, agent, after_cursor)
           ),
         {:ok, listing} <- listing(registration),
         {:ok, human_backing} <- human_backing(book) do
      {:ok,
       %{
         entries: Enum.flat_map(activity, &describe/1) ++ pairing(agent, next),
         next: next,
         listing: listing,
         human_backing: human_backing
       }}
    else
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # The registry page and the number the registry gave the agent.
  defp listing(nil), do: {:ok, nil}

  defp listing(%{"registryUrl" => "https://" <> _rest = url, "tokenId" => number})
       when is_binary(number),
       do: {:ok, %{url: url, number: number}}

  defp listing(_other), do: {:error, :registration_unreadable}

  defp human_backing(book) do
    case HumanBacking.read(book) do
      {:ok, backing} -> {:ok, backing}
      :error -> {:error, :agent_book_unreadable}
    end
  end

  # The pairing itself is the agent's own record here; the request that made
  # it was verified a moment before the agent existed.
  # It is the oldest entry, so it closes the last page.
  defp pairing(agent, nil),
    do: [
      %{site: "Regents Labs", action: "Paired with your account", occurred_at: agent.paired_at}
    ]

  defp pairing(_agent, _next), do: []

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

  defp request_options(config, agent, after_cursor) do
    [retry: false, receive_timeout: 5_000, connect_options: [timeout: 2_000]]
    |> Keyword.merge(Application.get_env(:regents, :siwa_req_options, []))
    |> Keyword.merge(
      auth: {:bearer, config.token},
      json: body(agent, after_cursor)
    )
  end

  defp body(agent, nil),
    do: %{wallet_address: agent.wallet, since: DateTime.to_iso8601(agent.paired_at)}

  defp body(agent, after_cursor), do: Map.put(body(agent, nil), :after, after_cursor)
end
