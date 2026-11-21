defmodule Regents.Keyfleet.Seasons.Preparations.OwnPick do
  @moduledoc "Narrows a read of picks to the Key the actor takes part as (`Regents.Keyfleet.Polls.voter/2`)."
  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, context) do
    case Regents.Keyfleet.Polls.voter(context.actor, Ash.Query.get_argument(query, :fleet_id)) do
      %{key: key} -> Ash.Query.filter(query, token_id == ^key)
      nil -> Ash.Query.filter(query, false)
    end
  end
end
