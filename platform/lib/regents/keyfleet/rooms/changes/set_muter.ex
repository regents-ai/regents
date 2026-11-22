defmodule Regents.Keyfleet.Rooms.Changes.SetMuter do
  @moduledoc "A new mute belongs to the actor adding it."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context),
    do:
      Ash.Changeset.force_change_attribute(
        changeset,
        :muter,
        Regents.Keyfleet.Rooms.Muter.of(context.actor)
      )
end
