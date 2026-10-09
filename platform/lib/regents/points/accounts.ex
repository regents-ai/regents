defmodule Regents.Points.Accounts do
  @moduledoc """
  What Regent Points asks this site about its accounts: the wallets an
  account's sign-in verified and the names of an account's own paired agents.
  """

  @behaviour RegentPoints.Accounts

  require Ash.Query

  alias Regents.Accounts
  alias Regents.Actors.System

  @impl true
  def human(id), do: Accounts.points_account!(id, actor: %System{})

  @impl true
  def agent_names(_id, []), do: {:ok, %{}}

  def agent_names(id, agent_ids) do
    query = Ash.Query.filter(RegentAgents.PairedAgent, id in ^agent_ids)

    # Reads as the account's own person, so the agents policy shows only that person's agents.
    with {:ok, account} <- Accounts.points_account(id, actor: %System{}),
         person = %RegentAgents.Person{privy_user_id: account.privy_user_id},
         {:ok, agents} <- RegentAgents.list_my_agents(query: query, actor: person) do
      {:ok, Map.new(agents, &{&1.id, &1.name})}
    end
  end
end
