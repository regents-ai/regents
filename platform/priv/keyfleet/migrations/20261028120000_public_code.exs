defmodule Regents.Repo.Migrations.KeyfleetPublicCode do
  @moduledoc """
  The Key holding a project makes the project's code at one commit public, as
  well as posts, items and saved pages (`Keyfleet.Projects.Publication`): each
  commit is public at most once in its project.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:publications) do
      add(:commit_hash, :text)
    end

    drop constraint(:publications, :publications_kind)
    drop constraint(:publications, :publications_shape)

    create constraint(:publications, :publications_kind,
             check: "kind IN ('posts', 'item', 'page', 'commit')",
             validate: false
           )

    create constraint(:publications, :publications_shape,
             check: """
             (kind = 'posts' AND room IS NOT NULL AND from_seq IS NOT NULL AND to_seq IS NOT NULL AND item IS NULL AND page IS NULL AND commit_hash IS NULL)
             OR (kind = 'item' AND item IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND page IS NULL AND commit_hash IS NULL)
             OR (kind = 'page' AND page IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND item IS NULL AND commit_hash IS NULL)
             OR (kind = 'commit' AND commit_hash IS NOT NULL AND room IS NULL AND from_seq IS NULL AND to_seq IS NULL AND item IS NULL AND page IS NULL)
             """,
             validate: false
           )

    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_kind")
    execute("ALTER TABLE keyfleet_app.publications VALIDATE CONSTRAINT publications_shape")

    create unique_index(:publications, [:fleet_id, :project, :commit_hash],
             name: :publications_one_per_commit_index
           )
  end
end
