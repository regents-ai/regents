defmodule RegentsWeb.Account.AccountSite do
  @moduledoc """
  This site's own part of the Agents page: beside each paired agent in the list
  (`RegentsWeb.Account.AgentsPanel`), shows any active Keyfleet check-in
  blocker the agent reported for its person (`Regents.Keyfleet.Agents.blocked_check_ins/2`).
  """
  use RegentsWeb, :html

  alias RegentAgents.Person
  alias Regents.Keyfleet.{Agents, Fleets}

  @doc """
  What this site shows for each of the account's agents, by the agent's wallet:
  a list of `{fleet_name, fleet_path, blocker}` entries from Keyfleet check-ins,
  or `:unavailable` if the read fails.
  """
  def read(%{privy_user_id: privy_user_id}, wallets)
      when is_binary(privy_user_id) and is_list(wallets) and wallets != [] do
    actor = %Person{privy_user_id: privy_user_id}

    case Agents.blocked_check_ins(Enum.take(wallets, 100), actor: actor) do
      {:ok, check_ins} ->
        check_ins
        |> Enum.filter(&(is_binary(&1.blocker) and &1.blocker != ""))
        |> Enum.group_by(& &1.acting_agent_wallet, fn check_in ->
          %{
            fleet_id: check_in.fleet_id,
            fleet_name: Fleets.name(check_in.fleet_id),
            fleet_path: Fleets.path(check_in.fleet_id),
            blocker: check_in.blocker
          }
        end)

      {:error, _error} ->
        Map.new(wallets, &{&1, :unavailable})
    end
  end

  def read(_account, _wallets), do: %{}

  attr :id, :string, required: true
  attr :part, :any, required: true, doc: "the agent's entry from `read/2`, or nil"

  @doc "Beside an agent in the list, before its own actions."
  def agent(%{part: [_ | _] = blockers} = assigns) do
    assigns = assign(assigns, :blockers, blockers)

    ~H"""
    <div id={@id} class="account-site-blockers">
      <p :for={item <- @blockers} class="account-kicker">
        <a href={item.fleet_path}>{item.fleet_name}</a>: {item.blocker}
      </p>
    </div>
    """
  end

  def agent(assigns), do: ~H""

  attr :id, :string, required: true
  attr :agent, :map, required: true, doc: "the agent that has just paired"
  attr :part, :any, required: true, doc: "its entry from `read/2`, or nil"

  @doc "Under the pairing box once the agent has paired."
  def paired(assigns), do: ~H""
end
