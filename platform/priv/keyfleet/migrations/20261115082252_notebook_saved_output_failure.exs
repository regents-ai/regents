defmodule Regents.Repo.Migrations.KeyfleetNotebookSavedOutputFailure do
  @moduledoc """
  How the run that made each kept notebook page failed, when it did
  (`Keyfleet.Notebooks.SavedOutput`): the stage it stopped at and the hub's
  sentence for it. Pages kept before it record none, and their rows stay as
  they are.
  """

  use Ecto.Migration

  def up do
    alter table(:notebook_saved_outputs) do
      add(:failure, :map)
    end
  end

  def down do
    alter table(:notebook_saved_outputs) do
      remove(:failure)
    end
  end
end
