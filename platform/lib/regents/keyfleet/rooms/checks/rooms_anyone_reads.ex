defmodule Regents.Keyfleet.Rooms.Checks.RoomsAnyoneReads do
  @moduledoc """
  Whether a room's posts are read in the fleet's rooms anyone reads
  (`Regents.Keyfleet.Rooms.Room.read_by_anyone/0`) by someone who may read each of
  them (`Regents.Keyfleet.Access`): the room `slug` names, or every room `slugs` names
  in a catch-up across rooms.
  """
  use Ash.Policy.SimpleCheck

  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Rooms.Room

  @impl true
  def describe(_opts), do: "every room read is one anyone reads"

  @impl true
  def match?(actor, %{subject: %Ash.Query{} = query}, _opts) do
    fleet_id = Ash.Query.get_argument(query, :fleet_id)

    Enum.all?(slugs(query), fn slug ->
      case Map.fetch(Room.read_by_anyone(), slug) do
        {:ok, component} -> Access.allowed?(actor, :read, component, fleet_id)
        :error -> false
      end
    end)
  end

  defp slugs(%Ash.Query{action: %{name: :catch_up}} = query),
    do: Ash.Query.get_argument(query, :slugs)

  defp slugs(query), do: [Ash.Query.get_argument(query, :slug)]
end
