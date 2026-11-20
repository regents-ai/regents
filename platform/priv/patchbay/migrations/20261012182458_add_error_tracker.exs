defmodule Regents.Repo.Migrations.PatchbayAddErrorTracker do
  @moduledoc "ErrorTracker's own tables, in the app's own schema."

  use Ecto.Migration

  def up,
    do: ErrorTracker.Migration.up(prefix: prefix(), create_schema: false)

  def down, do: ErrorTracker.Migration.down(prefix: prefix(), version: 1)
end
