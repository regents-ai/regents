defmodule Regents.Keyfleet.Dms.Changes.LoadSide do
  @moduledoc """
  Answers a conversation change with the changing Key's (`token_id`) view of
  it loaded: its last message (`Regents.Keyfleet.Dms.Preparations.LastShown`) and its
  `auto_delete_days`.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    side = Regents.Keyfleet.Dms.Preparations.LastShown.side(changeset.arguments.token_id)

    Ash.Changeset.after_action(changeset, fn _changeset, conversation ->
      # The action's policy has already admitted the holder of this Key to
      # this conversation; this reads back that same Key's side of it.
      Ash.load(conversation, side, authorize?: false)
    end)
  end
end
