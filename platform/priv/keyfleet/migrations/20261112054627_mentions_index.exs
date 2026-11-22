defmodule Regents.Repo.Migrations.KeyfleetMentionsIndex do
  @moduledoc """
  The index a Key's mentions are read through (`:mentioning` on
  `Keyfleet.Rooms.Message`). It is built concurrently, outside a transaction
  and without the migration lock, as Ecto documents, so posting goes on while
  it is built.

  A build that stops part-way, such as one that waited past the lock timeout
  for a long transaction, leaves the index marked invalid; drop it
  (`DROP INDEX CONCURRENTLY keyfleet_app.messages_mentions_index`) before
  running this again.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("SET lock_timeout = '5s'")

    create_if_not_exists(
      index(:messages, ["mentions"],
        name: "messages_mentions_index",
        concurrently: true,
        using: "gin"
      )
    )
  end

  def down do
    execute("SET lock_timeout = '5s'")

    drop_if_exists(index(:messages, [], name: "messages_mentions_index", concurrently: true))
  end
end
