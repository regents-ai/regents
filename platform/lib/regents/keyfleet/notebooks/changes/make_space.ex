defmodule Regents.Keyfleet.Notebooks.Changes.MakeSpace do
  @moduledoc """
  A project starting in a fleet with a notebook hub queues the job that makes
  its space there (`Regents.Keyfleet.Notebooks.Space`), in the same transaction as
  the project: a start rolled back queues nothing, and every project kept
  has its job.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.Space

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      if Notebooks.hub?(project.fleet_id),
        do: Oban.insert!(Space.new(%{fleet_id: project.fleet_id, project: project.name}))

      {:ok, project}
    end)
  end
end
