defmodule Regents.Repo.Migrations.KeyfleetAddErrorTracker do
  use Ecto.Migration

  # ErrorTracker's own tables, in the schema Keyfleet's own tables use.
  def up,
    do: ErrorTracker.Migration.up(prefix: prefix(), create_schema: false)

  def down, do: ErrorTracker.Migration.down(prefix: prefix(), version: 1)
end
