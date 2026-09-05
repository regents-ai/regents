defmodule AshPlatform.Staking.Checks.HumanActor do
  @moduledoc false
  use Ash.Policy.SimpleCheck

  alias AshPlatform.Actors.Human

  @impl true
  def describe(_opts), do: "actor is an authenticated human account"

  @impl true
  def match?(%Human{}, _context, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end
