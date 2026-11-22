defmodule Regents.Repo.Migrations.KeyfleetPublications do
  @moduledoc """
  What the fleets' Keys make public, for the workspace's Public place
  (`Keyfleet.Projects.Publication`). It starts empty.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    create table(:publications, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:fleet_id, :text, null: false)
      add(:project, :text, null: false)
      add(:key, :bigint, null: false)
      add(:author_wallet, :text, null: false)
      add(:kind, :text, null: false)
      add(:room, :text)
      add(:from_seq, :bigint)
      add(:to_seq, :bigint)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create index(:publications, [:fleet_id, :project, :inserted_at])

    create constraint(:publications, :publications_kind, check: "kind IN ('posts')")

    create constraint(:publications, :publications_range,
             check: "from_seq >= 1 AND to_seq >= from_seq AND to_seq - from_seq < 200"
           )
  end
end
