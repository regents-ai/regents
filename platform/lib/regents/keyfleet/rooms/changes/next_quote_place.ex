defmodule Regents.Keyfleet.Rooms.Changes.NextQuotePlace do
  @moduledoc """
  Gives a person's new request the next place in their own order in the
  fleet. The person's requests there are held in line until the transaction
  commits, so places are taken in the order they commit and an agent reading
  on from a place never skips one.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Keyfleet.Rooms.QuoteRequest

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.before_action(changeset, &place/1)

  defp place(changeset) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    account_id = Ash.Changeset.get_attribute(changeset, :human_account_id)

    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!(["quotes", fleet_id, account_id])
    ])

    # The server's own count of the person's places, which the action's
    # policy has already allowed them to add to.
    last =
      QuoteRequest
      |> Ash.Query.filter(fleet_id == ^fleet_id and human_account_id == ^account_id)
      |> Ash.max!(:seq, authorize?: false)

    Ash.Changeset.force_change_attribute(changeset, :seq, (last || 0) + 1)
  end
end
