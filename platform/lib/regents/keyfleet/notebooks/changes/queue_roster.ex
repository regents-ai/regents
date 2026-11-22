defmodule Regents.Keyfleet.Notebooks.Changes.QueueRoster do
  @moduledoc """
  A project's space recorded queues the fleet's roster run
  (`Regents.Keyfleet.Notebooks.Roster`) in the same transaction, so every member is
  made an editor of the new space. The shared `understanding` project's
  space also queues its first page (`Regents.Keyfleet.Notebooks.UnderstandingPage`).
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Notebooks.{Roster, UnderstandingPage}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      Oban.insert!(Roster.new(%{fleet_id: project.fleet_id}))

      if project.name == "understanding",
        do: Oban.insert!(UnderstandingPage.new(%{fleet_id: project.fleet_id}))

      {:ok, project}
    end)
  end
end
