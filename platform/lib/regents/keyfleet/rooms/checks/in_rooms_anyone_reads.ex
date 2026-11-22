defmodule Regents.Keyfleet.Rooms.Checks.InRoomsAnyoneReads do
  @moduledoc """
  The fleet's rooms anyone reads (`Regents.Keyfleet.Rooms.Room.read_by_anyone/0`), the
  Public room and the People and agents room, and the lines written in them,
  for reads that name their fleet and for whoever may read each room
  (`Regents.Keyfleet.Access`). A read without a fleet has none.

  For lines, the rooms' ids are found once, in the same statement, so the read
  keeps to its index on the fleet's room and time
  (`messages_fleet_room_lines_index`) rather than joining every line to its
  room.

  With `walls: true`, lines written on the fleet's Keys' walls count too, for
  whoever may read the walls (`:key_walls`), as a fleet's search reads them.
  """
  use Ash.Policy.FilterCheck

  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Rooms.Message
  alias Regents.Keyfleet.Rooms.Room

  @impl true
  def describe(_opts), do: "it is one of the fleet's rooms anyone reads, or a line in one"

  @impl true
  def filter(actor, %{query: %Ash.Query{} = query}, opts) do
    fleet_id = Ash.Query.get_argument(query, :fleet_id)

    if is_binary(fleet_id) do
      rooms =
        case readable(actor, fleet_id) do
          [] -> expr(false)
          slugs -> rooms(query.resource, fleet_id, slugs)
        end

      if opts[:walls] && Access.allowed?(actor, :read, :key_walls, fleet_id),
        do: expr(^rooms or in_key_thread),
        else: rooms
    else
      expr(false)
    end
  end

  defp readable(actor, fleet_id),
    do:
      for(
        {slug, component} <- Room.read_by_anyone(),
        Access.allowed?(actor, :read, component, fleet_id),
        do: slug
      )

  defp rooms(Room, _fleet_id, slugs), do: expr(slug in ^slugs)

  defp rooms(Message, fleet_id, slugs),
    do:
      expr(
        fragment(
          "? IN (SELECT anyone.id FROM keyfleet_app.rooms AS anyone WHERE anyone.fleet_id = ? AND anyone.slug = ANY(?))",
          room_id,
          ^fleet_id,
          ^slugs
        )
      )
end
