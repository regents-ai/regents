defmodule Regents.Repo.Migrations.KeyfleetLevelAndTopicRooms do
  @moduledoc """
  Gives every room its kind (core, level or topic) and the level whose rule it
  follows, if any.

  Generated with `mix ash.codegen`, then edited by hand so that the rooms
  already open, all of them core rooms, are marked as such before the column
  becomes required.
  """

  use Ecto.Migration

  def up do
    # Every room opened before this one is one of a fleet's three core rooms.
    alter table(:rooms) do
      add(:kind, :text, null: false, default: "core")
      add(:level, :bigint)
    end

    execute("ALTER TABLE keyfleet_app.rooms ALTER COLUMN kind DROP DEFAULT")

    create constraint(:rooms, :rooms_level_range,
             check: """
               level IS NULL OR level BETWEEN 1 AND 20
             """
           )

    create constraint(:rooms, :rooms_kind_shape,
             check: """
               (kind = 'core' AND level IS NULL AND slug !~ '^level-[0-9]+$')
             OR (kind = 'level' AND level IS NOT NULL AND slug = 'level-' || level)
             OR (kind = 'topic' AND slug !~ '^level-[0-9]+$')

             """
           )
  end

  def down do
    drop_if_exists(constraint(:rooms, :rooms_kind_shape))

    drop_if_exists(constraint(:rooms, :rooms_level_range))

    alter table(:rooms) do
      remove(:level)
      remove(:kind)
    end
  end
end
