defmodule RegentAgents.Person do
  @moduledoc """
  A signed-in person, named by their Privy user ID. The site builds it only
  from its own verified session. A site's team page builds it with
  `role: :admin`; `RegentAgents.Checks.Admin` then also asks that the
  `:admins` setting names the person.
  """
  @enforce_keys [:privy_user_id]
  defstruct [:privy_user_id, role: :person]

  @type t :: %__MODULE__{privy_user_id: String.t(), role: :person | :admin}
end

defmodule RegentAgents.Agent do
  @moduledoc """
  An agent whose signed request the SIWA service has just verified, named by
  its key's lowercase address, with the page of its listing in the agent
  registry when it has one, and the World ID person behind it with how many
  agents that person stands behind (`RegentAgents.HumanBacking`), which its
  pairing saves. Only `RegentAgents.HTTP` builds it, and, from the wallet alone,
  for the SIWA service's pairing read, whose token vouches for the agent.
  """
  @enforce_keys [:wallet]
  @derive {Inspect, except: [:human_id]}
  defstruct [:wallet, :registry_listing, :human_id, :same_person_agent_count, :chain_id,
             :verification_method, :receipt_expires_at]

  @type t :: %__MODULE__{
          wallet: String.t(),
          registry_listing: String.t() | nil,
          human_id: String.t() | nil,
          same_person_agent_count: pos_integer() | nil,
          chain_id: pos_integer() | nil,
          verification_method: String.t() | nil,
          receipt_expires_at: String.t() | nil
        }
end

defmodule RegentAgents.Checks.Person do
  @moduledoc "The actor is a signed-in person."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is a signed-in person"

  @impl true
  def match?(%RegentAgents.Person{privy_user_id: id}, _context, _opts), do: is_binary(id)
  def match?(_actor, _context, _opts), do: false
end

defmodule RegentAgents.Checks.Agent do
  @moduledoc "The actor is an agent whose signed request was verified."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is a verified agent"

  @impl true
  def match?(%RegentAgents.Agent{wallet: wallet}, _context, _opts), do: is_binary(wallet)
  def match?(_actor, _context, _opts), do: false
end

defmodule RegentAgents.Checks.OwnsAgent do
  @moduledoc "The actor is the signed-in person whose agent the change names in `paired_agent_id`."
  use Ash.Policy.SimpleCheck

  require Ash.Query

  @impl true
  def describe(_opts), do: "actor owns the paired agent"

  @impl true
  def match?(%RegentAgents.Person{privy_user_id: id}, %{changeset: changeset}, _opts)
      when is_binary(id) do
    agent_id = Ash.Changeset.get_attribute(changeset, :paired_agent_id)

    # This check is the authorization: the filter names the actor's own
    # Privy account, so it can only find an agent the actor owns.
    RegentAgents.PairedAgent
    |> Ash.Query.filter(id == ^agent_id and privy_user_id == ^id)
    |> Ash.exists?(authorize?: false)
  end

  def match?(_actor, _context, _opts), do: false
end

defmodule RegentAgents.Checks.Admin do
  @moduledoc """
  A team actor (`role: :admin`) whose Privy account the site's
  `config :regent_agents, admins: [...]` names. With no `:admins` setting, no
  one is.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is a Regent team member"

  @impl true
  def match?(%RegentAgents.Person{role: :admin, privy_user_id: id}, _context, _opts),
    do: id in Application.get_env(:regent_agents, :admins, [])

  def match?(_actor, _context, _opts), do: false
end
