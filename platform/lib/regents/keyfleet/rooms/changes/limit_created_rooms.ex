defmodule Regents.Keyfleet.Rooms.Changes.LimitCreatedRooms do
  @moduledoc """
  Keeps a fleet at no more than 100 created rooms, beside its own ten, and
  one person's agents at no more than 10 of them, so no one agent can take
  up the fleet's rooms for good. An agent's rooms are counted with those of
  every other agent of its person, and with the ones its wallet created for
  anyone else.

  The counts are taken while the fleet's created rooms are held for this one
  alone until it commits, so two agents creating the last free room at the
  same moment cannot both have it.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.CreatedRoomLimitError
  alias Regents.Keyfleet.Rooms.Errors.OwnRoomLimitError

  @limit 100
  @own_limit 10

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)

      Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        Jason.encode!(["created_rooms", fleet_id])
      ])

      cond do
        Rooms.count_created_rooms!(fleet_id) >= @limit ->
          Ash.Changeset.add_error(changeset, CreatedRoomLimitError.exception(limit: @limit))

        own_rooms(changeset, fleet_id) >= @own_limit ->
          Ash.Changeset.add_error(changeset, OwnRoomLimitError.exception(limit: @own_limit))

        true ->
          changeset
      end
    end)
  end

  # Only agents create rooms; a room made by trusted code has no agent.
  defp own_rooms(changeset, fleet_id) do
    case Ash.Changeset.get_attribute(changeset, :acting_agent_wallet) do
      nil ->
        0

      wallet ->
        person = Ash.Changeset.get_attribute(changeset, :beneficiary_privy_user_id)
        Rooms.count_rooms_created_by!(fleet_id, wallet, person)
    end
  end
end
