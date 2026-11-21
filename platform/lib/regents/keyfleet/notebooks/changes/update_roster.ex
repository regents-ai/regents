defmodule Regents.Keyfleet.Notebooks.Changes.UpdateRoster do
  @moduledoc """
  A key changing hands, or a shard of one issued or ended, queues the job that
  brings the fleet's notebook hub in step (`Regents.Keyfleet.Notebooks.Roster`), in
  the same transaction as the record: a record rolled back queues nothing,
  and every one kept has its job. A record read again from the chain, already
  made, queues nothing.

  With `ends: field`, a record whose `field` is still ahead (an issued shard's
  `expires_at`) also books a run for that moment, so access ends when the
  shard does.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.Roster

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      if Notebooks.hub?(record.fleet_id) and
           Ash.Resource.get_metadata(record, :upsert_skipped) != true do
        Oban.insert!(Roster.new(%{fleet_id: record.fleet_id}))
        book_end(record, opts[:ends])
      end

      {:ok, record}
    end)
  end

  defp book_end(_record, nil), do: :ok

  defp book_end(record, field) do
    ends_at = Map.fetch!(record, field)

    if ends_at && DateTime.after?(ends_at, DateTime.utc_now()),
      do:
        Oban.insert!(
          Roster.new(%{fleet_id: record.fleet_id}, scheduled_at: ends_at, unique: false)
        )
  end
end
