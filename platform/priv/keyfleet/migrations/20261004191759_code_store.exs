defmodule Regents.Repo.Migrations.KeyfleetCodeStore do
  @moduledoc """
  The fleets' code: each fleet's repository in the code store, and the
  branches and tags its key holders moved there.

  Generated with `mix ash.codegen`.
  """

  use Ecto.Migration

  def up do
    create table(:code_pushes, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:fleet_id, :text, null: false)
      add(:token_id, :bigint, null: false)
      add(:wallet, :text, null: false)
      add(:ref, :text, null: false)
      add(:head, :text, null: false)

      add(:pushed_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create index(:code_pushes, [:fleet_id, :pushed_at])

    create table(:code_repositories, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:owner, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end
  end

  def down do
    drop(table(:code_repositories))

    drop_if_exists(index(:code_pushes, [:fleet_id, :pushed_at]))

    drop(table(:code_pushes))
  end
end
