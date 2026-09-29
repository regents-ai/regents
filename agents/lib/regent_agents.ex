defmodule RegentAgents do
  @moduledoc """
  Agents people pair with their Regent account, shared by every Regent site.

  A person makes a pairing code on regents.sh and hands it to their agent. The
  agent signs `POST /api/agents/v1/pair` with its SIWA key on any Regent site,
  and from then on `GET /api/agents/v1/me` on every site answers with the same
  pairing. The person is named by their Privy user ID, which every site shares;
  the agent by the address of its key.

  Pairing says whose agent this is. What a paired agent may do on a site is that
  site's own decision.

  Each site supplies its repository, its PubSub, how it names a person's account
  in a check-in, and its SIWA audience:

      config :regent_agents,
        repo: MySite.Repo,
        pubsub: MySite.PubSub,
        account: {MySite.Agents, :account},
        siwa: [url: "https://siwa.regents.sh", audience: "mysite"]

  mounts the two agent requests, behind its own rate limit:

      forward "/api/agents/v1", RegentAgents.HTTP

  and starts `RegentAgents.Listener` after its repository and PubSub, so its
  pages hear agent changes made on every site.

  The schema is migrated once, from Regents, with `RegentAgents.Migrator`.
  """

  use Ash.Domain, otp_app: :regent_agents

  resources do
    resource RegentAgents.PairingCode do
      define :issue_pairing_code, action: :issue
    end

    resource RegentAgents.PairedAgent do
      define :pair_agent, action: :pair, args: [:code, :name, :harness]
      define :check_in_agent, action: :check_in
      define :list_my_agents, action: :mine
      define :get_my_agent, action: :mine_by_id, args: [:id], not_found_error?: false
      define :change_agent_harness, action: :change_harness, args: [:harness]
      define :unpair_agent, action: :unpair
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
