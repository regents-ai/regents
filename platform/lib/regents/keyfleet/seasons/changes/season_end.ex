defmodule Regents.Keyfleet.Seasons.Changes.SeasonEnd do
  @moduledoc "Sets a new season's end, three hours after its start (`Regents.Keyfleet.Seasons.ends_at/1`)."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :starts_at) do
      %DateTime{} = starts_at ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :ends_at,
          Regents.Keyfleet.Seasons.ends_at(starts_at)
        )

      nil ->
        changeset
    end
  end
end
