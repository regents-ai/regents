defmodule Regents.Keyfleet.Notebooks.Backups do
  @moduledoc """
  Copies the code of every notebook in one fleet that changed since its last
  copy (`Regents.Keyfleet.Notebooks.Backup`), in every project not deleted, archived
  ones included. A notebook changed when its hub last saved it after its
  newest copy, or it has none yet.

  Queued once a day for every fleet with a notebook hub
  (`Regents.Keyfleet.Notebooks.DailyBackup`). Runs go one at a time on their own
  queue, `notebook_backups`, so they never hold back a roster run. A run that
  stops part way is run again from the start: a copy already kept for a
  change is not kept twice.
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_backups,
    max_attempts: 10,
    unique: [keys: [:fleet_id], period: :infinity, states: [:available, :retryable]]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.{Backup, HubClient}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}}) do
    with true <- Notebooks.hub?(fleet_id) || {:cancel, :no_hub},
         {:ok, projects} <- Projects.projects(fleet_id, actor: %System{}) do
      newest =
        Map.new(
          Notebooks.newest_backups!(fleet_id, actor: %System{}),
          &{&1.notebook_id, &1.changed_at}
        )

      locks = Notebooks.locks(fleet_id)

      projects
      |> Enum.reject(&is_nil(&1.hub_project_id))
      |> in_turn(&copy_project(fleet_id, &1, newest, locks))
    end
  end

  defp copy_project(fleet_id, project, newest, locks) do
    with {:ok, notebooks} <- HubClient.all_notebooks(fleet_id, project.hub_project_id) do
      notebooks
      |> Enum.filter(&changed?(&1, newest))
      |> in_turn(&copy(fleet_id, project, &1, locks[&1["id"]]))
    end
  end

  # Each in turn, stopping at the first that isn't done.
  defp in_turn(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp changed?(%{"id" => id, "updated_at" => updated_at}, newest) do
    case newest[id] do
      nil -> true
      copied -> DateTime.after?(changed_at(updated_at), copied)
    end
  end

  # A notebook deleted since it was listed has nothing to copy.
  defp copy(fleet_id, project, notebook, lock) do
    case HubClient.content(fleet_id, project.hub_project_id, notebook["id"]) do
      {:ok, nil} ->
        :ok

      {:ok, code} ->
        Backup
        |> Ash.Changeset.for_create(
          :keep,
          %{
            fleet_id: fleet_id,
            project: project.name,
            notebook_id: notebook["id"],
            title: notebook["title"],
            code: code,
            author: notebook["author"],
            key: lock && lock.key,
            unlocked: lock != nil and not lock.locked,
            changed_at: changed_at(notebook["updated_at"])
          },
          actor: %System{}
        )
        |> Ash.create!()

        :ok

      error ->
        error
    end
  end

  defp changed_at(updated_at) do
    {:ok, at, _offset} = DateTime.from_iso8601(updated_at)
    at
  end
end
