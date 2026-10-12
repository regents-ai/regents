defmodule Regents.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  # ErrorTracker's own tables, in the schema the site's own tables use.
  def up,
    do: ErrorTracker.Migration.up(prefix: Regents.Repo.default_prefix(), create_schema: false)

  def down, do: ErrorTracker.Migration.down(prefix: Regents.Repo.default_prefix(), version: 1)
end
