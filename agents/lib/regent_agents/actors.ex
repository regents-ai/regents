defmodule RegentAgents.Person do
  @moduledoc """
  A signed-in person, named by their Privy user ID. The site builds it only
  from its own verified session.
  """
  @enforce_keys [:privy_user_id]
  defstruct [:privy_user_id]

  @type t :: %__MODULE__{privy_user_id: String.t()}
end

defmodule RegentAgents.Agent do
  @moduledoc """
  An agent whose signed request the SIWA service has just verified, named by
  its key's lowercase address, with the page of its listing in the agent
  registry when it has one, and whether a person verified with World ID stands
  behind it. Only `RegentAgents.HTTP` builds it.
  """
  @enforce_keys [:wallet]
  defstruct [:wallet, :registry_listing, human_backed: false]

  @type t :: %__MODULE__{
          wallet: String.t(),
          registry_listing: String.t() | nil,
          human_backed: boolean()
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
