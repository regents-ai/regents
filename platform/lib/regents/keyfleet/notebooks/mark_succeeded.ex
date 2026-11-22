defmodule Regents.Keyfleet.Notebooks.MarkSucceeded do
  @moduledoc """
  Marks the copies of one fleet's run pages kept before each copy recorded
  whether its run succeeded (`Regents.Keyfleet.Notebooks.SavedOutput`): every such
  copy of a run the fleet's hub names succeeded, so a notebook's last good
  page is there from the day the record starts. It only ever sets
  `succeeded` from false to true on those copies, and changes and deletes
  nothing else. A copy of a run the hub no longer holds (it keeps runs 30
  days) stays as it was.

  Queued once for each fleet with a notebook hub by `backfill/0`, run by
  hand on the release that adds `succeeded`. It reads only the notebooks
  with such copies, in the fleet's projects, waits its turn with the other
  hub calls (the `keyfleet_notebook_hubs` queue runs one job), and a fleet's job is
  queued again only once the last has run. One that stops part way is run
  again from the start: marking a copy twice changes nothing. A hub that
  does not answer is waited for first
  (`Regents.Keyfleet.Notebooks.HubClient.wait_while_away/2`).
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id], period: :infinity, states: :incomplete]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.HubClient

  @doc """
  Queues the job for every fleet with a notebook hub. Run once by hand on
  the release (`bin/keyfleet rpc 'Regents.Keyfleet.Notebooks.MarkSucceeded.backfill()'`),
  with the owner's go: it writes to the production database.
  `{:ok, fleets_queued}`.
  """
  def backfill do
    fleet_ids = Notebooks.hub_fleet_ids()
    Enum.each(fleet_ids, &Oban.insert!(new(%{fleet_id: &1})))
    {:ok, length(fleet_ids)}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}} = job) do
    with true <- Notebooks.hub?(fleet_id) || {:cancel, :no_hub},
         {:ok, unmarked} <- Notebooks.unmarked_run_outputs(fleet_id, actor: %System{}),
         do: fleet_id |> mark(unmarked) |> HubClient.wait_while_away(job)
  end

  defp mark(_fleet_id, []), do: :ok

  defp mark(fleet_id, unmarked) do
    with {:ok, projects} <- Projects.projects(fleet_id, actor: %System{}),
         notebook_ids = MapSet.new(unmarked, & &1.notebook_id),
         {:ok, succeeded} <- succeeded_runs(fleet_id, projects, notebook_ids) do
      succeeded = MapSet.new(succeeded)
      run_ids = for %{source_id: id} <- unmarked, MapSet.member?(succeeded, id), do: id

      Notebooks.SavedOutput
      |> Ash.Query.for_read(:of_sources, %{fleet_id: fleet_id, source_ids: run_ids},
        actor: %System{}
      )
      |> Notebooks.mark_succeeded(
        actor: %System{},
        bulk_options: [strategy: :atomic, notify?: false, return_errors?: true]
      )
      |> case do
        %Ash.BulkResult{status: :success} -> :ok
        %Ash.BulkResult{errors: errors} -> {:error, errors}
      end
    end
  end

  # The runs the hub names succeeded, of every job of the projects'
  # notebooks among `notebook_ids`.
  defp succeeded_runs(fleet_id, projects, notebook_ids) do
    for(%{hub_project_id: space} when is_binary(space) <- projects, do: space)
    |> in_turn(fn space ->
      with {:ok, notebooks} <- HubClient.all_notebooks(fleet_id, space) do
        notebooks
        |> Enum.filter(&MapSet.member?(notebook_ids, &1["id"]))
        |> in_turn(&notebook_runs(fleet_id, space, &1["id"]))
      end
    end)
  end

  defp notebook_runs(fleet_id, space, notebook_id) do
    with {:ok, jobs} <- HubClient.jobs(fleet_id, space, notebook_id),
         do: in_turn(jobs, &job_runs(fleet_id, space, notebook_id, &1["id"]))
  end

  defp job_runs(fleet_id, space, notebook_id, job_id) do
    with {:ok, runs} <- HubClient.runs(fleet_id, space, notebook_id, job_id),
         do: {:ok, for(%{"status" => "succeeded", "run_id" => id} <- runs, do: id)}
  end

  # Each in turn, all they found, stopping at the first that fails.
  defp in_turn(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, found} ->
      case fun.(item) do
        {:ok, more} -> {:cont, {:ok, more ++ found}}
        error -> {:halt, error}
      end
    end)
  end
end
