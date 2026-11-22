defmodule Regents.Keyfleet.Rooms.Changes.LimitRenames do
  @moduledoc """
  Lets an open room be renamed at most once a minute, counted from when it was
  last named.

  The time is read while the room is held for this naming alone, so two members
  renaming it at the same moment cannot both get through. Naming a room what it
  is already called is not a rename and is never refused here.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Rooms.Errors.RenameTooSoonError
  alias Regents.Keyfleet.Rooms.Sequence

  @interval_ms 60_000

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :topic),
      do: Ash.Changeset.before_action(changeset, &hold_to_interval/1),
      else: changeset
  end

  defp hold_to_interval(changeset) do
    room = changeset.data
    Sequence.lock_room!(room.id)

    # The room as it stands now that it is held; the naming itself was already
    # authorized, and anyone may read a room.
    %{topic_set_at: named_at} =
      Regents.Keyfleet.Rooms.get_room!(room.fleet_id, room.slug, authorize?: false)

    wait_ms =
      if named_at,
        do: @interval_ms - DateTime.diff(DateTime.utc_now(), named_at, :millisecond),
        else: 0

    if wait_ms > 0,
      do:
        Ash.Changeset.add_error(
          changeset,
          RenameTooSoonError.exception(retry_after: ceil(wait_ms / 1000))
        ),
      else: changeset
  end
end
