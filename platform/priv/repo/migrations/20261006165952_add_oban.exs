defmodule Regents.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's job table, in the schema the site's own tables use.
  def up, do: Oban.Migrations.up(prefix: "regents_app")
  def down, do: Oban.Migrations.down(prefix: "regents_app")
end
