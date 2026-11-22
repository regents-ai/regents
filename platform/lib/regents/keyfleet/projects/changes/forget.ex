defmodule Regents.Keyfleet.Projects.Changes.Forget do
  @moduledoc """
  Deleting a project takes everything people and agents could see of it
  away, in the transaction that marks it deleted: its items, the links from
  or to them and the changes that touched them leave the workspace's read
  tables, and its pins, its pushes, the daily copies of its notebooks and
  its work counted in the Atlas go. The same transaction queues the
  jobs that delete its notebook space from the hub
  (`Regents.Keyfleet.Notebooks.DeleteSpace`) and its repository from the code store
  (`Regents.Keyfleet.Code.DeleteRepository`).

  It holds the fleet's cursor first, as each page the projector copies does
  (`Regents.Keyfleet.Graph.Projection`), so a page copied at the same time either
  lands before and is deleted here, or lands after and leaves the deleted
  project out. The graph's own log keeps the record that the items existed:
  it is never rewritten.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.Atlas
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Code.DeleteRepository
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Notebooks.DeleteSpace

  @system %Regents.Account.Actors.System{}

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.after_action(changeset, fn _changeset, project -> forget(project) end)

  defp forget(%{fleet_id: fleet_id, name: name} = project) do
    Graph.hold_cursor!(fleet_id, actor: @system)

    arguments = %{fleet_id: fleet_id, project: name}

    # Links first: they are found through the project's items.
    for {resource, destroy} <- [
          {Graph.Relation, :remove},
          {Graph.Object, :forget},
          {Graph.Event, :forget},
          {Graph.Pin, :forget},
          {Code.Push, :forget},
          {Regents.Keyfleet.Notebooks.Backup, :forget},
          {Atlas.Thing, :forget},
          {Atlas.Bucket, :forget},
          {Atlas.Notebook, :forget}
        ] do
      resource
      |> Ash.Query.for_read(:of_project, arguments, actor: @system)
      |> Ash.bulk_destroy!(destroy, %{},
        actor: @system,
        strategy: [:atomic],
        return_errors?: true
      )
    end

    Oban.insert!(
      DeleteSpace.new(%{fleet_id: fleet_id, project: name, space: project.hub_project_id})
    )

    Oban.insert!(DeleteRepository.new(%{repository: project.repository}))
    {:ok, project}
  end
end
