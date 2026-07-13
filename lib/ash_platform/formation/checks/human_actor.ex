defmodule AshPlatform.Formation.Checks.HumanActor do
  use Ash.Policy.SimpleCheck

  alias AshPlatform.Actors.Human

  @impl true
  def describe(_opts), do: "actor is the signed-in human principal"

  @impl true
  def match?(%Human{human_account_id: id}, _context, _opts) when is_integer(id), do: true
  def match?(_actor, _context, _opts), do: false
end
