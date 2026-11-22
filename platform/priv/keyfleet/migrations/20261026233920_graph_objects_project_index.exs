defmodule Regents.Repo.Migrations.KeyfleetGraphObjectsProjectIndex do
  @moduledoc """
  The index that lists one project's workspace objects, most recently changed
  first. It is built concurrently, outside a transaction and without the
  migration lock, as Ecto documents, so writes to the workspace go on while
  it is built.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:graph_objects, [:fleet_id, :project, :type, :changed_seq, :id],
             name: "graph_objects_project_changed_index",
             concurrently: true
           )
  end
end
