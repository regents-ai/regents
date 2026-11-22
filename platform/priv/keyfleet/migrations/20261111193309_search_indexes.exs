defmodule Regents.Repo.Migrations.KeyfleetSearchIndexes do
  @moduledoc """
  The indexes a fleet's search reads (`Keyfleet.Search`): the words of the
  posts in rooms and on Keys' walls, of direct messages, and of the
  workspace's items, each matched as English; an item over 250,000 bytes is
  left out, since Postgres holds at most 1MB of words for one row. Nothing
  that exists changes.
  Each index is built concurrently, outside a transaction and without the
  migration lock, as Ecto documents, so posting, messaging and the workspace
  go on while it is built.

  A build that stops part-way, such as one that waited past the lock timeout
  for a long transaction, leaves its index marked invalid; drop that index
  (`DROP INDEX CONCURRENTLY keyfleet_app.<name>`) before running this again.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("SET lock_timeout = '5s'")

    create_if_not_exists(
      index(:messages, ["to_tsvector('english', body)"],
        name: "messages_search_index",
        concurrently: true,
        using: "gin",
        where: "kind = 'post'"
      )
    )

    create_if_not_exists(
      index(:dm_messages, ["to_tsvector('english', body)"],
        name: "dm_messages_search_index",
        concurrently: true,
        using: "gin"
      )
    )

    create_if_not_exists(
      index(:graph_objects, ["jsonb_to_tsvector('english', data, '[\"string\"]')"],
        name: "graph_objects_search_index",
        concurrently: true,
        using: "gin",
        where: "octet_length(data::text) <= 250000"
      )
    )
  end

  def down do
    execute("SET lock_timeout = '5s'")

    drop_if_exists(index(:graph_objects, [], name: "graph_objects_search_index", concurrently: true))
    drop_if_exists(index(:dm_messages, [], name: "dm_messages_search_index", concurrently: true))
    drop_if_exists(index(:messages, [], name: "messages_search_index", concurrently: true))
  end
end
