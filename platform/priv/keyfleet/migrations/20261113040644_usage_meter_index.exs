defmodule Regents.Repo.Migrations.KeyfleetUsageMeterIndex do
  @moduledoc """
  The index a month's posts are counted through (`:written_between` on
  `Keyfleet.Rooms.Message`). It is built concurrently, outside a transaction
  and without the migration lock, as Ecto documents, so posting goes on while
  it is built.

  A build that stops part-way, such as one that waited past the lock timeout
  for a long transaction, leaves the index marked invalid; drop it
  (`DROP INDEX CONCURRENTLY keyfleet_app.messages_posts_written_index`) before
  running this again.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("SET lock_timeout = '5s'")

    create_if_not_exists(
      index(:messages, ["fleet_id", "inserted_at"],
        name: "messages_posts_written_index",
        concurrently: true,
        where: "kind = 'post'"
      )
    )
  end

  def down do
    execute("SET lock_timeout = '5s'")

    drop_if_exists(index(:messages, [], name: "messages_posts_written_index", concurrently: true))
  end
end
