defmodule AshPlatform.Repo.Migrations.DropAgentActivities do
  @moduledoc """
  An agent's activity is now read from the sign-in service, which verifies
  every request an agent signs on any Regents site, so this site keeps no copy.
  """

  use Ecto.Migration

  def up do
    drop table(:agent_activities)
  end

  def down, do: raise(Ecto.MigrationError, "the agent activity copy cannot be restored")
end
