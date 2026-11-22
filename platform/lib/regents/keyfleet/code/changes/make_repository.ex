defmodule Regents.Keyfleet.Code.Changes.MakeRepository do
  @moduledoc """
  A project starting queues the job that makes its repository in the code
  store (`Regents.Keyfleet.Code.Setup`), in the same transaction as the project: a
  start rolled back queues nothing, and every project kept has its job.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Code.Setup

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, project ->
      Oban.insert!(Setup.new(%{repository: project.repository}))
      {:ok, project}
    end)
  end
end
