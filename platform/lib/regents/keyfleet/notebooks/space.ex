defmodule Regents.Keyfleet.Notebooks.Space do
  @moduledoc """
  Makes one project's space in its fleet's notebook hub: a hub project the
  provisioner owns, named after the project's title and tagged
  `keyfleet/<project name>`, kept on the project as `hub_project_id`.
  Recording it queues the fleet's roster run (`Regents.Keyfleet.Notebooks.Roster`),
  which makes every member an editor of the new space.

  Queued in the transaction that starts the project
  (`Regents.Keyfleet.Notebooks.Changes.MakeSpace`), and by a roster run for any of
  the fleet's projects still without a space, as when a fleet's hub is set up
  after its projects started. Runs go one at a time, behind roster runs, on
  the `keyfleet_notebook_hubs` queue, and one run per project waits at a time. A run
  that made the space and stopped before recording it finds the space again
  by its tag, so a project never gets two. A run still waiting when its
  project is deleted makes nothing. One whose project is deleted while it
  makes the space records nothing (`Regents.Keyfleet.Projects.Project`'s
  `record_space`), and its next try finds the project gone and stops. The
  delete run removes the space by its tag when it looks after the space was
  made. The one-run limit holds on each machine, so while two machines run,
  a delete run can look before the space is made and leave it on the hub.
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id, :project], period: :infinity, states: [:available, :retryable]]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.HubClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id, "project" => name}}) do
    project = Projects.project!(fleet_id, name, actor: %System{})

    cond do
      not Notebooks.hub?(fleet_id) -> {:cancel, :no_hub}
      is_nil(project) -> {:cancel, :project_deleted}
      project.hub_project_id -> :ok
      true -> make(project)
    end
  end

  defp make(project) do
    tag = "keyfleet/" <> project.name
    provisioner = HubClient.provisioner(project.fleet_id)

    with {:ok, spaces} <- HubClient.projects(project.fleet_id),
         {:ok, space} <- ours(spaces, provisioner, tag) || create(project, tag),
         {:ok, _project} <- Projects.record_space(project, space, actor: %System{}) do
      :ok
    end
  end

  defp ours(spaces, provisioner, tag) do
    Enum.find_value(spaces, fn
      %{"id" => id, "owner" => ^provisioner, "tags" => tags} -> if tag in tags, do: {:ok, id}
      _space -> nil
    end)
  end

  defp create(project, tag) do
    with {:ok, %{"id" => space}} <-
           HubClient.create_project(project.fleet_id, project.title, [tag]) do
      {:ok, space}
    end
  end
end
