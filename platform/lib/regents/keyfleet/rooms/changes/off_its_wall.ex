defmodule Regents.Keyfleet.Rooms.Changes.OffItsWall do
  @moduledoc """
  A removal names the wall and the post. The post must be on that wall, and
  the wallet holding that Key now is read here and kept with the removal, so
  the removal's own rule (`Regents.Keyfleet.Rooms.WallRemoval`) asks about the Key the
  post was really written to. Anything that isn't a post on the named wall is
  refused.
  """
  use Ash.Resource.Change

  alias Ash.Changeset
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Rooms.Message

  @impl true
  def change(changeset, _opts, _context) do
    # The post is read whoever asks: the removal's own policy then decides, from
    # the wall named here, whether this reader may take it off.
    fleet_id = Changeset.get_attribute(changeset, :fleet_id)
    token_id = Changeset.get_attribute(changeset, :token_id)

    with id when is_binary(id) <- Changeset.get_attribute(changeset, :message_id),
         {:ok, %{kind: :post, room: %{kind: :key, fleet_id: ^fleet_id, token_id: ^token_id}}} <-
           Ash.get(Message, id, load: [:room], authorize?: false, not_found_error?: false),
         %{owner_wallet: holder} <- Keys.current_key!(fleet_id, token_id) do
      Changeset.force_change_attribute(changeset, :holder_wallet, holder)
    else
      _not_on_this_wall ->
        Changeset.add_error(changeset,
          field: :message_id,
          message: "is not a post on this Key's wall"
        )
    end
  end
end
