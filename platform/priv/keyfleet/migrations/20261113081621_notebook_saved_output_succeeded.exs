defmodule Regents.Repo.Migrations.KeyfleetNotebookSavedOutputSucceeded do
  @moduledoc """
  Whether each kept notebook page (`Keyfleet.Notebooks.SavedOutput`) is a
  background run's that succeeded, as the hub names the run when it answers
  the page. Pages kept before it start as not, since no hub named the run
  then; a notebook's last good page is the next one kept from a run that
  succeeded.
  """

  use Ecto.Migration

  def up do
    alter table(:notebook_saved_outputs) do
      add(:succeeded, :boolean, null: false, default: false)
    end
  end

  def down do
    alter table(:notebook_saved_outputs) do
      remove(:succeeded)
    end
  end
end
