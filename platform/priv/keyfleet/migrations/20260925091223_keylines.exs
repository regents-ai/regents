defmodule Regents.Repo.Migrations.KeyfleetKeylines do
  @moduledoc """
  Marks every line in a key's thread as one, so the fleet's room lines are
  indexed and read without their rooms.

  Generated with `mix ash.codegen keylines`, then edited: the mark arrives
  false on every line already written, and only the lines in keys' threads are
  then marked, before the default goes. Lines are never edited, so their guard
  is lifted for that one update. Every line in a key's thread names its key, so
  the update never meets a line the key rule was added without checking.
  """

  use Ecto.Migration

  def up do
    alter table(:messages) do
      add(:in_key_thread, :boolean, null: false, default: false)
    end

    execute("ALTER TABLE keyfleet_app.messages DISABLE TRIGGER immutable_messages")

    execute("""
    UPDATE keyfleet_app.messages AS line
    SET in_key_thread = true
    FROM keyfleet_app.rooms AS room
    WHERE room.id = line.room_id AND room.kind = 'key'
    """)

    execute("ALTER TABLE keyfleet_app.messages ENABLE TRIGGER immutable_messages")

    execute("ALTER TABLE keyfleet_app.messages ALTER COLUMN in_key_thread DROP DEFAULT")

    drop_if_exists(
      index(:messages, ["fleet_id", "as_key", "inserted_at DESC"],
        name: "messages_posts_as_key_index"
      )
    )

    create index(:messages, ["fleet_id", "as_key", "inserted_at DESC"],
             name: "messages_posts_as_key_index",
             where: "kind = 'post' AND NOT in_key_thread"
           )

    drop_if_exists(
      index(:messages, ["fleet_id", "inserted_at DESC", "id"], name: "messages_fleet_lines_index")
    )

    create index(:messages, ["fleet_id", "inserted_at DESC", "id"],
             name: "messages_fleet_lines_index",
             where: "NOT in_key_thread"
           )
  end

  def down do
    drop_if_exists(
      index(:messages, ["fleet_id", "inserted_at DESC", "id"], name: "messages_fleet_lines_index")
    )

    create index(:messages, ["fleet_id", "inserted_at DESC", "id"],
             name: "messages_fleet_lines_index",
             where: "kind IN ('post', 'room_named')"
           )

    drop_if_exists(
      index(:messages, ["fleet_id", "as_key", "inserted_at DESC"],
        name: "messages_posts_as_key_index"
      )
    )

    create index(:messages, ["fleet_id", "as_key", "inserted_at DESC"],
             name: "messages_posts_as_key_index",
             where: "kind = 'post'"
           )

    alter table(:messages) do
      remove(:in_key_thread)
    end
  end
end
