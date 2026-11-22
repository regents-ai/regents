defmodule Regents.Keyfleet.Rooms.Changes.NameRoom do
  @moduledoc """
  Names an open room and says so in the room.

  The room takes a short line saying who named it and what, in its next place,
  and keeps that line's author and time as who named the room and when. Naming
  a room what it is already called changes nothing and adds no line, so asking
  again is always safe.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Rooms

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    if Ash.Changeset.changing_attribute?(changeset, :topic) do
      changeset
      |> Ash.Changeset.before_action(&say_so(&1, actor))
      |> Ash.Changeset.after_action(&with_line/2)
    else
      changeset
    end
  end

  defp say_so(changeset, actor) do
    room = changeset.data

    case Rooms.note_room_named(
           %{
             fleet_id: room.fleet_id,
             slug: room.slug,
             body: Ash.Changeset.get_attribute(changeset, :topic),
             idempotency_key: Ash.UUID.generate()
           },
           actor: actor
         ) do
      {:ok, line} ->
        changeset
        |> Ash.Changeset.put_context(:naming_line, line)
        |> Ash.Changeset.force_change_attributes(%{
          topic_set_by: line.author_wallet,
          topic_set_at: line.inserted_at
        })

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  # The room is answered with the line counted in its head.
  defp with_line(changeset, room),
    do: {:ok, %{room | head_seq: changeset.context.naming_line.seq}}
end
