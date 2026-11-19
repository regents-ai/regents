defmodule RegentAgents do
  @moduledoc """
  Agents people pair with their Regent account, shared by every Regent site.

  A person makes a pairing code with Pair New Agent on a Regent site's
  Agents page and hands it to their agent. The agent signs `POST /api/agents/v1/pair` with its SIWA key on any Regent site,
  and from then on `GET /api/agents/v1/me` on every site answers with the same
  pairing. The person is named by their Privy user ID, which every site shares;
  the agent by the address of its key.

  Pairing says whose agent this is. What a paired agent may do on a site is that
  site's own decision, and `GET /api/agents/v1/whoami` tells the agent in its
  own words.

  Each site supplies its repository, its PubSub, how it names a person's account
  in a check-in, the person's profile code on a hello card
  (`RegentAgents.HelloCard`), what an agent may do there in each status, and its
  SIWA audience and first origin:

      config :regent_agents,
        repo: MySite.Repo,
        pubsub: MySite.PubSub,
        account: {MySite.Agents, :account},
        person: {MySite.Agents, :person},
        allowed: %{"not_paired" => [...], "person_not_here" => [...], "paired" => [...]},
        siwa: [url: "https://siwa.regents.sh", audience: "mysite", origin: "https://mysite.example"]

  mounts the agent requests, behind its own rate limit:

      forward "/api/agents/v1", RegentAgents.HTTP

  and starts `RegentAgents.Listener` after its PubSub and its own
  `Postgrex.Notifications` connection (the `:notifications` setting), so its
  pages hear agent changes made on every site.

  The `person` function takes the person's Privy user ID and gives their
  profile code, the id of their shared Regent profile, never the Privy user ID,
  an email, a wallet or a name. Nil means the person is paired but has no
  profile code yet, and the SIWA service's pairing read is answered
  `person_has_no_profile` (409).

  The schema is migrated once, from Regents, with `RegentAgents.Migrator`.
  """

  use Ash.Domain, otp_app: :regent_agents

  import Ecto.Query, only: [from: 2, where: 3, order_by: 3, limit: 2, distinct: 3]

  resources do
    resource RegentAgents.PairingCode do
      define :issue_pairing_code, action: :issue
      define :agents_paired_with, action: :paired_with, args: [:codes]
    end

    resource RegentAgents.PairedAgent do
      define :pair_agent, action: :pair, args: [:code, :name, :harness]
      define :check_in_agent, action: :check_in, args: [:privy_user_id]
      define :current_pairing, action: :by_wallet, not_found_error?: false
      define :list_my_agents, action: :mine
      define :get_my_agent, action: :mine_by_id, args: [:id], not_found_error?: false
      define :rename_agent, action: :rename, args: [:name]
      define :unpair_agent, action: :unpair
    end

    resource RegentAgents.AgentPicture do
      define :set_agent_picture, action: :set, args: [:paired_agent_id, :bytes]
      define :remove_agent_picture, action: :remove, get_by: [:paired_agent_id]
      define :remove_agent_picture_by_team, action: :remove_by_team, get_by: [:paired_agent_id]
      define :agent_picture, action: :by_wallet, args: [:wallet], not_found_error?: false
    end
  end

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_agents, :repo)

  @doc """
  The PubSub topic that hears when a person's agents change: paired, checked
  in, corrected or unpaired on any Regent site.
  """
  @spec topic(String.t()) :: String.t()
  def topic(privy_user_id), do: "regent_agents:" <> privy_user_id

  @typedoc """
  One pairing, kept after an unpair: `revoked_at` is nil while it lasts. Its `id`
  is the `paired_agent_id` of the `:agent_paired` signal.
  """
  @type pairing :: %{
          id: Ecto.UUID.t(),
          privy_user_id: String.t(),
          wallet: String.t(),
          name: String.t(),
          paired_at: DateTime.t(),
          revoked_at: DateTime.t() | nil
        }

  @doc "The pairing with this id, whether or not it has been unpaired."
  @spec pairing_history(Ecto.UUID.t()) :: {:ok, pairing() | nil}
  def pairing_history(id) do
    {:ok, repo(nil, :read).one(where(pairings(), [h], h.id == type(^id, Ecto.UUID)))}
  end

  @doc "Every pairing a person has had, oldest first, unpaired ones included."
  @spec pairing_histories(String.t()) :: {:ok, [pairing()]}
  def pairing_histories(privy_user_id) do
    pairings()
    |> where([h], h.privy_user_id == ^privy_user_id)
    |> order_by([h], asc: h.paired_at, asc: h.id)
    |> repo(nil, :read).all()
    |> then(&{:ok, &1})
  end

  @doc """
  The pairing that held `wallet`, a lowercase address, at `at`: paired at or
  before `at` and not unpaired by then. No such pairing, or more than one, is
  `:unknown_owner`; it never answers with a later or current pairing.
  """
  @spec pairing_at(String.t(), DateTime.t()) :: {:ok, pairing()} | {:error, :unknown_owner}
  def pairing_at(wallet, %DateTime{} = at) do
    pairings()
    |> where([h], h.wallet == ^wallet and h.paired_at <= type(^at, :utc_datetime_usec))
    |> where([h], is_nil(h.revoked_at) or h.revoked_at > type(^at, :utc_datetime_usec))
    |> limit(2)
    |> repo(nil, :read).all()
    |> case do
      [pairing] -> {:ok, pairing}
      _none_or_many -> {:error, :unknown_owner}
    end
  end

  # How many people one read of `pairings_held_from_before/1` takes.
  @held_page 500

  @doc """
  Each person's earliest pairing made before `at` that is still paired, one per
  person, in order of their Privy user ID: the agents people already had at `at`,
  such as the time the Points start run reads them.

  A lazy stream. It reads #{@held_page} people at a time as it is walked, each read
  starting after the last person of the one before, in no transaction, so the caller
  can write between reads. Pairings are shared by every Regent site, so every site
  gets the same list.
  """
  @spec pairings_held_from_before(DateTime.t()) :: Enumerable.t(pairing())
  def pairings_held_from_before(%DateTime{} = at) do
    nil
    |> Stream.unfold(fn
      :done -> nil
      after_person -> held_page(at, after_person)
    end)
    |> Stream.concat()
  end

  defp held_page(at, after_person) do
    pairings()
    |> where([h], h.paired_at < type(^at, :utc_datetime_usec) and is_nil(h.revoked_at))
    |> after_person(after_person)
    |> distinct([h], asc: h.privy_user_id)
    |> order_by([h], asc: h.paired_at, asc: h.id)
    |> limit(@held_page)
    |> repo(nil, :read).all()
    |> case do
      [] -> nil
      page when length(page) < @held_page -> {page, :done}
      page -> {page, List.last(page).privy_user_id}
    end
  end

  defp after_person(query, nil), do: query
  defp after_person(query, person), do: where(query, [h], h.privy_user_id > ^person)

  defp pairings do
    from h in "pairing_history",
      prefix: "regent_agents",
      select: %{
        id: type(h.id, Ecto.UUID),
        privy_user_id: h.privy_user_id,
        wallet: h.wallet,
        name: h.name,
        paired_at: type(h.paired_at, :utc_datetime_usec),
        revoked_at: type(h.revoked_at, :utc_datetime_usec)
      }
  end

  @doc false
  def channel, do: "regent_agents"

  @doc false
  # Tells every site through the shared database. Inside a transaction the
  # notice goes out when it commits, and not at all if it rolls back.
  def announce(privy_user_id) do
    Ecto.Adapters.SQL.query!(repo(nil, :mutate), "SELECT pg_notify($1, $2)", [
      channel(),
      privy_user_id
    ])

    :ok
  end

  @doc false
  def lock(privy_user_id) do
    <<key::signed-64, _rest::binary>> = :crypto.hash(:sha256, "regent_agents:" <> privy_user_id)
    Ecto.Adapters.SQL.query!(repo(nil, :mutate), "SELECT pg_advisory_xact_lock($1)", [key])
  end
end
