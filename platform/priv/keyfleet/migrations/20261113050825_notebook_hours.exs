defmodule Regents.Repo.Migrations.KeyfleetNotebookHours do
  @moduledoc """
  Each fleet's notebook hours: the machines read from its hub
  (`Keyfleet.Usage.Machine`), a new, empty table, and each month's
  `notebook_seconds` (`Keyfleet.Usage.Month`), a new column that every month
  already counted starts without, so those months show no figure.
  """

  use Ecto.Migration

  def up do
    create table(:notebook_machines, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:id, :text, null: false, primary_key: true)
      add(:kind, :text, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)
      add(:seen_at, :utc_datetime_usec, null: false)
    end

    create index(:notebook_machines, ["fleet_id", "(coalesce(ended_at, seen_at))"],
             name: "notebook_machines_counted_index"
           )

    alter table(:fleet_usage) do
      add(:notebook_seconds, :bigint)
    end
  end

  def down do
    alter table(:fleet_usage) do
      remove(:notebook_seconds)
    end

    drop_if_exists(
      index(:notebook_machines, ["fleet_id", "(coalesce(ended_at, seen_at))"],
        name: "notebook_machines_counted_index"
      )
    )

    drop(table(:notebook_machines))
  end
end
