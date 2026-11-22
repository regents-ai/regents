defmodule Regents.Repo.Migrations.KeyfleetProjects do
  @moduledoc """
  Makes projects, and gives every fleet recorded so far its first one,
  `general`, titled "General", archived and held by Key 3 (Key 329 in Regents Club): it keeps the
  fleet's repository, named after the fleet, and the fleet's notebook space,
  moved over from `notebook_hubs`, which goes.
  """

  use Ecto.Migration

  def up do
    create table(:projects, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:name, :text, null: false, primary_key: true)
      add(:title, :text, null: false)
      add(:created_by_key, :bigint)
      add(:key, :bigint, null: false)
      add(:state, :text, null: false)
      add(:repository, :text, null: false)
      add(:hub_project_id, :text)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    create unique_index(:projects, [:repository], name: "projects_one_repository_index")

    create unique_index(:projects, [:fleet_id, :key],
             name: "projects_one_active_per_key_index",
             where: "state = 'active'"
           )

    create constraint(:projects, :projects_state, check: "state IN ('active', 'archived', 'deleted')")

    create constraint(:projects, :projects_name_shape,
             check: """
               name ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(name) <= 32
             """
           )

    execute("""
    INSERT INTO keyfleet_app.projects (fleet_id, name, title, key, state, repository, hub_project_id)
    SELECT fleet.id, 'general', 'General',
           CASE fleet.id WHEN 'regents_club' THEN 329 ELSE 3 END,
           'archived', fleet.id, hub.project_id
    FROM keyfleet_app.fleets AS fleet
    LEFT JOIN keyfleet_app.notebook_hubs AS hub ON hub.fleet_id = fleet.id
    """)

    drop(table(:notebook_hubs))
  end

  def down do
    create table(:notebook_hubs, primary_key: false) do
      add(:fleet_id, :text, null: false, primary_key: true)
      add(:project_id, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    execute("""
    INSERT INTO keyfleet_app.notebook_hubs (fleet_id, project_id)
    SELECT fleet_id, hub_project_id
    FROM keyfleet_app.projects
    WHERE name = 'general' AND hub_project_id IS NOT NULL
    """)

    drop_if_exists(constraint(:projects, :projects_name_shape))
    drop_if_exists(constraint(:projects, :projects_state))

    drop_if_exists(
      unique_index(:projects, [:fleet_id, :key], name: "projects_one_active_per_key_index")
    )

    drop_if_exists(unique_index(:projects, [:repository], name: "projects_one_repository_index"))

    drop(table(:projects))
  end
end
