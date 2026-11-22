defmodule Regents.Repo.Migrations.KeyfleetNotebookRunSources do
  @moduledoc """
  What each background run started through this site ran from
  (`Keyfleet.Notebooks.RunSource`). It starts empty.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:notebook_run_sources, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:run_id, :text, null: false, primary_key: true)
      add(:notebook_id, :text, null: false)
      add(:code_sha256, :text, null: false)
      add(:files, {:array, :map}, null: false, default: [])
      add(:files_complete, :boolean, null: false)

      add(:started_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create constraint(:notebook_run_sources, :notebook_run_sources_code_sha256,
             check: "code_sha256 ~ '^[0-9a-f]{64}$'"
           )
  end
end
