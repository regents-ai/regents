defmodule Regents.Repo.Migrations.KeyfleetProjectsInGraph do
  @moduledoc """
  Gives every workspace object, every pin and every change copied from the
  workspace's log the project it belongs to: a change, every project whose
  items it touched. Everything made before projects belongs to its fleet's
  first project, `general`. The index that lists one project's objects is
  built without blocking writes, by the next migration.
  """

  use Ecto.Migration

  def up do
    alter table(:graph_objects) do
      add(:project, :text, null: false, default: "general")
    end

    alter table(:graph_objects) do
      modify(:project, :text, default: nil)
    end

    alter table(:graph_events) do
      add(:projects, {:array, :text}, null: false, default: ["general"])
    end

    alter table(:graph_events) do
      modify(:projects, {:array, :text}, default: nil)
    end

    alter table(:workspace_pins) do
      add(:project, :text, null: false, default: "general")
    end

    alter table(:workspace_pins) do
      modify(:project, :text, default: nil)
    end

    drop(
      unique_index(:workspace_pins, [:fleet_id, :place, :target],
        name: "workspace_pins_one_per_target_index"
      )
    )

    create unique_index(:workspace_pins, [:fleet_id, :project, :place, :target],
             name: "workspace_pins_one_per_target_index"
           )
  end

  def down do
    drop(
      unique_index(:workspace_pins, [:fleet_id, :project, :place, :target],
        name: "workspace_pins_one_per_target_index"
      )
    )

    execute("DELETE FROM keyfleet_app.workspace_pins WHERE project <> 'general'")

    create unique_index(:workspace_pins, [:fleet_id, :place, :target],
             name: "workspace_pins_one_per_target_index"
           )

    alter table(:workspace_pins) do
      remove(:project)
    end

    alter table(:graph_events) do
      remove(:projects)
    end

    alter table(:graph_objects) do
      remove(:project)
    end
  end
end
