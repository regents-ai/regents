defmodule Regents.Repo.Migrations.KeyfleetPublicPages do
  @moduledoc """
  A Key makes public a saved notebook page it made, as well as its posts and
  items (`Keyfleet.Projects.Publication`): each page is public at most once.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:publications) do
      add(:page, :text)
    end

    drop constraint(:publications, :publications_kind)
    drop constraint(:publications, :publications_shape)

    create constraint(:publications, :publications_kind,
             check: "kind IN ('posts', 'item', 'page')",
             validate: false
           )

    create constraint(:publications, :publications_shape,
             check: """
             (kind = 'posts' AND room IS NOT NULL AND from_seq IS NOT NULL AND to_seq IS NOT NULL AND item IS NULL AND page IS NULL)
             OR (kind = 'item' AND item IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND page IS NULL)
             OR (kind = 'page' AND page IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND item IS NULL)
             """,
             validate: false
           )

    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_kind")
    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_shape")

    create unique_index(:publications, [:fleet_id, :page], name: :publications_one_per_page_index)
  end
end
