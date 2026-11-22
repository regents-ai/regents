defmodule Regents.Keyfleet.Rooms.Sequence do
  @moduledoc """
  The place each post takes in its own room's order.

  Every room counts its posts itself, so one room's order never depends on
  another room's traffic and a reader can ask for everything after the place it
  last read. The count is kept on the room row and moved by the statement below
  inside the posting transaction. It is the only write to rooms made outside a
  resource action.
  """

  @doc "Holds every write to one room's order, posts and namings, in line until the transaction commits."
  def lock_room!(room_id) do
    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!(["room", room_id])
    ])

    :ok
  end

  @doc "Takes the next place in this room's order, and holds the room until commit."
  def next!(room_id) do
    %Postgrex.Result{rows: [[seq]]} =
      Regents.Repo.query!(
        "UPDATE keyfleet_app.rooms SET head_seq = head_seq + 1 WHERE id = $1 RETURNING head_seq",
        [Ecto.UUID.dump!(room_id)]
      )

    seq
  end
end
