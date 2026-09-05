defmodule AshPlatform.Repo.Migrations.RemoveTechtreeComments do
  use Ecto.Migration

  def up do
    execute("DELETE FROM discussions.comments WHERE target_type = 'techtree_node'")
  end

  def down do
    # Deleted techtree_node comments are not recoverable.
    :ok
  end
end
