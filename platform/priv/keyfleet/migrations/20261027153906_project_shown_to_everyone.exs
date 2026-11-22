defmodule Regents.Repo.Migrations.KeyfleetProjectShownToEveryone do
  @moduledoc """
  Whether a project's page shows its work to everyone. Every project starts
  shown to members only, but Virtual Cell in Classic #1, which the founder
  chose to show (27 Oct 2026).
  """

  use Ecto.Migration

  def up do
    alter table(:projects) do
      add(:shown_to_everyone, :boolean, null: false, default: false)
    end

    execute("""
    UPDATE keyfleet_app.projects SET shown_to_everyone = true
    WHERE fleet_id = 'fleet_tech_classic' AND name = 'virtual-cell'
    """)
  end

  def down do
    alter table(:projects) do
      remove(:shown_to_everyone)
    end
  end
end
