defmodule Regents.Repo.Migrations.KeyfleetKeyThreads do
  @moduledoc """
  Gives every line in a room the key it was written as, and every key a thread
  of its own: a room of kind `key` at the address `key-N`, which no created
  room may take and whose name no other room's name clashes with. A thread's
  address is its key's, so the existing address index keeps a key to one
  thread and finds it; the fleet's own rooms get an index of their own.

  Generated with `mix ash.codegen`, then edited by hand so that the key check
  on lines is added without checking the lines already written, which can
  never be changed, and so that it cannot be undone (see `down/0`). The new
  address rule on created rooms is checked against the rooms already there,
  so a created room already at a key's address stops the migration rather
  than being changed.
  """

  use Ecto.Migration

  def up do
    alter table(:messages) do
      add(:as_key, :bigint)
    end

    create constraint(:messages, :messages_as_key,
             check: """
               as_key IS NOT NULL AND as_key > 0
             """,
             validate: false
           )

    create index(:messages, ["fleet_id", "as_key", "inserted_at DESC"],
             name: "messages_posts_as_key_index",
             where: "kind = 'post'"
           )

    alter table(:rooms) do
      add(:token_id, :bigint)
    end

    drop_if_exists(constraint(:rooms, :rooms_kind_address))

    create constraint(:rooms, :rooms_kind_address,
             check: """
               (kind = 'fixed' AND slug IN ('welcome', 'general', 'business', 'voting', 'coding'))
             OR (kind = 'open' AND slug IN ('open-1', 'open-2', 'open-3', 'open-4', 'open-5'))
             OR (kind = 'created' AND slug NOT IN ('welcome', 'general', 'business', 'voting', 'coding', 'open-1', 'open-2', 'open-3', 'open-4', 'open-5')
                 AND slug !~ '^key-[0-9]+$')
             OR (kind = 'key' AND token_id IS NOT NULL AND slug = 'key-' || token_id)

             """
           )

    create constraint(:rooms, :rooms_key_thread_token,
             check: """
               (kind = 'key') = (token_id IS NOT NULL)
             """
           )

    create index(:rooms, ["fleet_id", "slug"],
             name: "rooms_fleet_rooms_index",
             where: "kind <> 'key'"
           )

    drop_if_exists(
      index(:rooms, ["fleet_id", "lower(coalesce(topic, name))"],
        name: "rooms_unique_name_per_fleet"
      )
    )

    create index(:rooms, ["fleet_id", "lower(coalesce(topic, name))"],
             name: "rooms_unique_name_per_fleet",
             unique: true,
             where: "kind <> 'key'"
           )
  end

  # Lines can never be deleted, so a key's thread and its posts stay once
  # written, and the rooms' old rules refuse a thread. Removing `as_key` would
  # also lose which key wrote every line. There is no way back that keeps the
  # history.
  def down do
    raise Ecto.MigrationError,
      message:
        "key threads cannot be undone: their posts can never be deleted, and every line's key would be lost"
  end
end
