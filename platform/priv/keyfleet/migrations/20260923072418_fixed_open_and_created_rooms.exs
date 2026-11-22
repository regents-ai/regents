defmodule Regents.Repo.Migrations.KeyfleetFixedOpenAndCreatedRooms do
  @moduledoc """
  Replaces level rooms with each fleet's fixed, open and created rooms: drops
  the level column and its checks, adds an open room's topic with who named it
  and when, and marks each line in a room as a post or a naming. No two rooms
  of a fleet may go by the same name, whatever its case: a room goes by its
  topic once it has one, and by its name otherwise.

  Generated with `mix ash.codegen`, then edited by hand so that the rooms and
  posts already there are kept: every post so far is a post, a room at one of
  the new fixed or open addresses becomes that room, and every other room,
  including the old planning, work and level rooms, becomes a created room.
  Rolling back does the reverse.
  """

  use Ecto.Migration

  @fixed "('welcome', 'general', 'business', 'voting', 'coding')"
  @open "('open-1', 'open-2', 'open-3', 'open-4', 'open-5')"

  def up do
    alter table(:messages) do
      add(:kind, :text, null: false, default: "post")
    end

    execute("ALTER TABLE keyfleet_app.messages ALTER COLUMN kind DROP DEFAULT")

    create constraint(:messages, :messages_kind,
             check: """
               kind IN ('post', 'room_named')
             """
           )

    alter table(:rooms) do
      add(:topic, :text)
      add(:topic_set_by, :text)
      add(:topic_set_at, :utc_datetime_usec)
    end

    drop_if_exists(constraint(:rooms, :rooms_level_range))
    drop_if_exists(constraint(:rooms, :rooms_kind_shape))

    alter table(:rooms) do
      remove(:level)
    end

    execute("""
    UPDATE keyfleet_app.rooms
    SET kind = CASE
      WHEN slug IN #{@fixed} THEN 'fixed'
      WHEN slug IN #{@open} THEN 'open'
      ELSE 'created'
    END
    """)

    create constraint(:rooms, :rooms_kind_address,
             check: """
               (kind = 'fixed' AND slug IN ('welcome', 'general', 'business', 'voting', 'coding'))
             OR (kind = 'open' AND slug IN ('open-1', 'open-2', 'open-3', 'open-4', 'open-5'))
             OR (kind = 'created' AND slug NOT IN ('welcome', 'general', 'business', 'voting', 'coding', 'open-1', 'open-2', 'open-3', 'open-4', 'open-5'))

             """
           )

    create constraint(:rooms, :rooms_topic_named,
             check: """
               (topic IS NULL AND topic_set_by IS NULL AND topic_set_at IS NULL)
             OR (kind = 'open' AND topic IS NOT NULL AND topic_set_by IS NOT NULL
                 AND topic_set_by ~ '^0x[0-9a-f]{40}$' AND topic_set_at IS NOT NULL)

             """
           )

    create index(:rooms, ["fleet_id", "lower(coalesce(topic, name))"],
             name: "rooms_unique_name_per_fleet",
             unique: true
           )
  end

  def down do
    drop_if_exists(
      index(:rooms, ["fleet_id", "lower(coalesce(topic, name))"],
        name: "rooms_unique_name_per_fleet"
      )
    )

    drop_if_exists(constraint(:rooms, :rooms_topic_named))
    drop_if_exists(constraint(:rooms, :rooms_kind_address))

    alter table(:rooms) do
      remove(:topic_set_at)
      remove(:topic_set_by)
      remove(:topic)
      add(:level, :bigint)
    end

    execute("""
    UPDATE keyfleet_app.rooms
    SET kind = CASE
          WHEN slug IN ('general', 'planning', 'work') THEN 'core'
          WHEN slug ~ '^level-([1-9]|1[0-9]|20)$' THEN 'level'
          ELSE 'topic'
        END,
        level = CASE
          WHEN slug ~ '^level-([1-9]|1[0-9]|20)$' THEN substring(slug FROM 7)::bigint
        END
    """)

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

    drop_if_exists(constraint(:messages, :messages_kind))

    alter table(:messages) do
      remove(:kind)
    end
  end
end
