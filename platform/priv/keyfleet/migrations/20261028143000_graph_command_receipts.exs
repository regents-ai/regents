defmodule Regents.Repo.Migrations.KeyfleetGraphCommandReceipts do
  @moduledoc """
  The index that finds the record a workspace write left of itself by its
  command id, so an agent asks whether a write ran without sending it again
  (`Keyfleet.Graph.Event`'s `:command` read). It is built concurrently,
  outside a transaction and without the migration lock, as Ecto documents,
  so writes to the workspace go on while it is built.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:graph_events, ["fleet_id", "(payload ->> 'command_id')"],
                           name: "graph_events_command_id_index",
                           where: "type = 'keyfleet.command'",
                           concurrently: true
                         )
  end
end
