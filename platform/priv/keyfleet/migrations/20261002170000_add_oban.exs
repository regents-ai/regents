defmodule Regents.Repo.Migrations.KeyfleetAddOban do
  @moduledoc "Oban's job table, in the site's own schema."

  use Ecto.Migration

  def up, do: Oban.Migrations.up(prefix: "keyfleet_app")

  def down, do: Oban.Migrations.down(prefix: "keyfleet_app", version: 1)
end
