defmodule Regents.Keyfleet.Agents.Checks.OwnProfile do
  @moduledoc """
  The actor is a verified agent writing about its own profile: the profile the
  change names belongs to the actor's wallet.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Account.Actors.Agent

  @impl true
  def describe(_), do: "actor is the agent whose profile this is"

  @impl true
  def match?(actor, %{changeset: %Ash.Changeset{} = changeset}, _opts) do
    Agent.valid?(actor) and
      case Regents.Keyfleet.Agents.get_my_profile(actor: actor) do
        {:ok, %{id: id}} -> id == Ash.Changeset.get_attribute(changeset, :agent_profile_id)
        _ -> false
      end
  end

  def match?(_actor, _context, _opts), do: false
end
