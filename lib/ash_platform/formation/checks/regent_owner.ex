defmodule AshPlatform.Formation.Checks.RegentOwner do
  use Ash.Policy.SimpleCheck

  alias AshPlatform.Actors.Human

  @impl true
  def describe(_opts), do: "actor owns the Regent"

  @impl true
  def match?(
        %Human{human_account_id: actor_id},
        %{changeset: %{data: %{human_account_id: owner_id}}},
        _opts
      ),
      do: actor_id == owner_id

  def match?(_actor, _context, _opts), do: false
end
