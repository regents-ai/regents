defmodule Regents.Keyfleet.Atlas.ReadHub do
  @moduledoc """
  Reads the notebooks of each of one fleet's projects from its hub and counts
  what changed into the Atlas, queued every hour by `Regents.Keyfleet.Atlas.ReadHubs`.

  A notebook new to the Atlas is counted as made at its `created_at`, and as
  saved at its `updated_at` when that is later; one updated since it was
  last listed is counted as saved at its new `updated_at`. So a notebook
  saved many times in an hour counts as one save that hour, at its last. Each
  is counted as the Key its maker writes as (`Regents.Keyfleet.Notebooks.keys/2`) and
  kept (`Regents.Keyfleet.Atlas.Notebook`) for the next read to compare with.

  A project is read from an hour before its notebook updated last, so a save
  the last read only just missed is still seen; a project read for the first
  time is read whole. Each project is counted in one transaction that holds
  the project's row, so a project deleted meanwhile is either counted and then
  forgotten whole, or not counted at all. A read that fails stops the run;
  the next hour's read finds everything it would have, from the same place.

  It waits its turn with the other hub calls (the `keyfleet_notebook_hubs` queue runs
  one job), and a fleet's read is queued again only once the last has run.
  Once done it tells the fleet's Atlas readers (`Regents.Keyfleet.Atlas.changed/1`).
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 1,
    unique: [keys: [:fleet_id], period: :infinity, states: :incomplete]

  alias Regents.Keyfleet.{Atlas, Notebooks, Projects}
  alias Regents.Keyfleet.Atlas.{Count, Source}
  alias Regents.Keyfleet.Notebooks.HubClient

  @system %Regents.Account.Actors.System{}
  @overlap_seconds 3_600
  @tables [Projects.Project, Atlas.Notebook, Atlas.Thing, Atlas.Bucket]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fleet_id" => fleet_id}}) do
    with {:ok, spaces} <- Notebooks.spaces(fleet_id),
         :ok <- read_spaces(fleet_id, spaces) do
      Atlas.changed(fleet_id)
      :ok
    end
  end

  defp read_spaces(fleet_id, spaces) do
    Enum.reduce_while(spaces, :ok, fn {project, space}, :ok ->
      case listed(fleet_id, project, space) do
        {:ok, listed} ->
          count(fleet_id, project, space, listed)
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp listed(fleet_id, project, space) do
    case Atlas.last_updated_notebook!(fleet_id, project, actor: @system) do
      nil ->
        HubClient.all_notebooks(fleet_id, space)

      last ->
        after_time = DateTime.add(last.updated_at, -@overlap_seconds)
        HubClient.notebooks_changed_after(fleet_id, space, after_time)
    end
  end

  defp count(_fleet_id, _project, _space, []), do: :ok

  defp count(fleet_id, project, space, listed) do
    notebooks = Enum.map(listed, &notebook(&1, fleet_id, project, space))
    keys = Notebooks.keys(fleet_id, notebooks)
    notebooks = Enum.map(notebooks, &%{&1 | key: keys[&1.id]})

    {:ok, _} =
      Ash.transact(@tables, fn ->
        if live?(fleet_id, project) do
          kept =
            fleet_id
            |> Atlas.notebooks_with_ids!(Enum.map(notebooks, & &1.id), actor: @system)
            |> Map.new(&{&1.id, &1})

          Count.count(fleet_id, Enum.flat_map(notebooks, &touches(&1, kept[&1.id])))
          Atlas.keep_notebooks!(notebooks, actor: @system)
        end
      end)

    :ok
  end

  defp live?(fleet_id, project) do
    case Projects.locked_project!(fleet_id, project, actor: @system) do
      %{state: :deleted} -> false
      nil -> false
      _project -> true
    end
  end

  defp notebook(listed, fleet_id, project, space) do
    %{
      fleet_id: fleet_id,
      id: listed["id"],
      project: project,
      space: space,
      title: listed["title"],
      author: listed["author"],
      key: nil,
      created_at: time(listed["created_at"]),
      updated_at: time(listed["updated_at"])
    }
  end

  defp time(iso) do
    {:ok, at, _offset} = DateTime.from_iso8601(iso)
    at
  end

  defp touches(notebook, nil) do
    made = touch(notebook, notebook.created_at)

    if DateTime.after?(notebook.updated_at, notebook.created_at),
      do: [made, touch(notebook, notebook.updated_at)],
      else: [made]
  end

  defp touches(notebook, kept) do
    if DateTime.after?(notebook.updated_at, kept.updated_at),
      do: [touch(notebook, notebook.updated_at)],
      else: []
  end

  defp touch(notebook, at) do
    %{
      thing: notebook.id,
      kind: Source.notebook_kind(),
      project: notebook.project,
      at: at,
      key: notebook.key
    }
  end
end
