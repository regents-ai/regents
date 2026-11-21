defmodule Regents.Keyfleet.Checks.AgentActor do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_), do: "actor is a verified Keyfleet wallet principal"

  @impl true
  def match?(actor, _context, _opts), do: Regents.Account.Actors.Agent.valid?(actor)
end
