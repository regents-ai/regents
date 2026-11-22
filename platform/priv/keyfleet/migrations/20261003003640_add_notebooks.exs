defmodule Regents.Repo.Migrations.KeyfleetAddNotebooks do
  @moduledoc """
  The fleets' notebook hubs: the project each hub's key holders work in, and
  the one-time links that open a fleet's notebooks.

  Generated with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    create table(:notebook_handoffs, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:code_hash, :binary, null: false)
      add(:fleet_id, :text, null: false)
      add(:human_account_id, :bigint, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:used_at, :utc_datetime_usec)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create unique_index(:notebook_handoffs, [:code_hash],
             name: "notebook_handoffs_unique_code_hash_index"
           )

    create table(:notebook_hubs, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:project_id, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end
  end

  def down do
    drop(table(:notebook_hubs))

    drop_if_exists(
      unique_index(:notebook_handoffs, [:code_hash],
        name: "notebook_handoffs_unique_code_hash_index"
      )
    )

    drop(table(:notebook_handoffs))
  end
end
