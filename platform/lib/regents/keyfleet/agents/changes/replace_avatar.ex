defmodule Regents.Keyfleet.Agents.Changes.ReplaceAvatar do
  @moduledoc """
  Queues the deletion of the picture a profile had before this change, in the
  change's own transaction. The action locks the profile first
  (`get_and_lock_for_update`), so the picture replaced is the one it really had.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Agents.DeleteAvatar

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, profile ->
      previous = changeset.data.avatar_key

      if previous && previous != profile.avatar_key,
        do: Oban.insert!(DeleteAvatar.new(%{key: previous}))

      {:ok, profile}
    end)
  end
end
