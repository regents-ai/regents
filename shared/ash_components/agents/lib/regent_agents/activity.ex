defmodule RegentAgents.Activity do
  @moduledoc """
  Where a paired agent has been active across the Regent sites since it was
  paired, a line per site and day for the last 30 days, newest day first, and its
  listing in the agent registry, if it has one. The SIWA service keeps both: it
  counts each request it verifies for an agent under the site and the day, and
  an agent lists itself through it.

  A site reads them with its own reader key, which the SIWA service lists among
  its activity readers:

      config :regent_agents, activity_read_token: System.get_env("SIWA_ACTIVITY_READ_TOKEN")

  Without the key, or without an https SIWA address, every read answers
  `{:error, :not_configured}`.

  The SIWA service answers each site's reads up to 600 a minute, all of a site
  machine's reads together, so a site keeps each agent's reading for a few
  minutes and shares it with every page that shows that agent.
  """

  alias RegentAgents.{Broker, PairedAgent}

  @sites %{
    "ash-template" => "Ash Template",
    "regents" => "Regents Labs",
    "regents-mobile" => "Regents mobile app",
    "autolaunch" => "Autolaunch",
    "techtree" => "Techtree",
    "patchbay" => "Patchbay",
    "keyfleet" => "Keyfleet",
    "chainagent" => "Chainagent"
  }

  @type day :: %{
          site: String.t(),
          day: Date.t(),
          first_seen_at: DateTime.t(),
          last_seen_at: DateTime.t()
        }
  @type listing :: %{url: String.t(), number: String.t()}
  @type reading :: %{days: [day()], listing: listing() | nil}

  @doc """
  The agent's days on the Regent sites since it was paired, newest day first and
  each day's sites by name, and its registry listing. A day missing a field, or
  with a value that does not read as a date or time, makes the whole read
  `{:error, :bad_day}`; an answer without a list of days is `{:error, :bad_days}`.
  """
  @spec recent(PairedAgent.t()) :: {:ok, reading()} | {:error, term()}
  def recent(%PairedAgent{} = agent) do
    with {:ok, config} <- config(),
         {:ok,
          %Req.Response{
            status: 200,
            body: %{"data" => %{"days" => days, "agentRegistration" => registration}}
          }}
         when is_list(days) <-
           Broker.request(
             method: :post,
             url: config.base_url <> "/api/shared/siwa/activity",
             receive_timeout: 5_000,
             connect_options: [timeout: 2_000],
             auth: {:bearer, config.token},
             json: %{wallet_address: agent.wallet, since: DateTime.to_iso8601(agent.paired_at)}
           ),
         {:ok, listing} <- listing(registration),
         {:ok, days} <- days(days) do
      {:ok, %{days: days, listing: listing}}
    else
      {:ok, %Req.Response{status: 200}} -> {:error, :bad_days}
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Where and when the agent was last active, or nil before its first request."
  @spec latest(reading()) :: %{site: String.t(), at: DateTime.t()} | nil
  def latest(%{days: []}), do: nil

  def latest(%{days: days}) do
    newest = Enum.max_by(days, & &1.last_seen_at, DateTime)
    %{site: newest.site, at: newest.last_seen_at}
  end

  # The registry page and the number the registry gave the agent.
  defp listing(nil), do: {:ok, nil}

  defp listing(%{"registryUrl" => "https://" <> _rest = url, "tokenId" => number})
       when is_binary(number),
       do: {:ok, %{url: url, number: number}}

  defp listing(_other), do: {:error, :registration_unreadable}

  # Days at sites outside the Regent family are left out. A day in any other shape
  # makes the whole reading unreadable.
  defp days(days) do
    read = Enum.map(days, &day/1)

    if {:error, :bad_day} in read,
      do: {:error, :bad_day},
      else: {:ok, for({:ok, %{} = day} <- read, do: day)}
  end

  defp day(%{
         "audience" => audience,
         "day" => day,
         "first_seen_at" => first_seen_at,
         "last_seen_at" => last_seen_at
       })
       when is_binary(audience) and is_binary(day) and is_binary(first_seen_at) and
              is_binary(last_seen_at) do
    with {:ok, day} <- Date.from_iso8601(day),
         {:ok, first_seen_at, _offset} <- DateTime.from_iso8601(first_seen_at),
         {:ok, last_seen_at, _offset} <- DateTime.from_iso8601(last_seen_at) do
      case Map.fetch(@sites, audience) do
        {:ok, site} ->
          {:ok, %{site: site, day: day, first_seen_at: first_seen_at, last_seen_at: last_seen_at}}

        :error ->
          {:ok, nil}
      end
    else
      _unreadable -> {:error, :bad_day}
    end
  end

  defp day(_other), do: {:error, :bad_day}

  defp config do
    base_url = Application.fetch_env!(:regent_agents, :siwa)[:url]
    token = Application.get_env(:regent_agents, :activity_read_token)

    case {base_url, token} do
      {"https://" <> _rest, token} when is_binary(token) and token != "" ->
        {:ok, %{base_url: String.trim_trailing(base_url, "/"), token: token}}

      _missing ->
        {:error, :not_configured}
    end
  end
end
