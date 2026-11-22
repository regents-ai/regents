defmodule Regents.Repo.Migrations.KeyfleetPublicItems do
  @moduledoc """
  A Key makes public a workspace item it made, as well as its posts
  (`Keyfleet.Projects.Publication`): each item is public at most once.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:publications) do
      add(:item, :text)
    end

    drop constraint(:publications, :publications_kind)

    create constraint(:publications, :publications_kind,
             check: "kind IN ('posts', 'item')",
             validate: false
           )

    create constraint(:publications, :publications_shape,
             check: """
             (kind = 'posts' AND room IS NOT NULL AND from_seq IS NOT NULL AND to_seq IS NOT NULL AND item IS NULL)
             OR (kind = 'item' AND item IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL)
             """,
             validate: false
           )

    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_kind")
    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_shape")

    create unique_index(:publications, [:fleet_id, :item], name: :publications_one_per_item_index)
  end
end
