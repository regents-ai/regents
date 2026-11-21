defmodule Regents.Keyfleet.Notebooks.DeleteSpace do
  @moduledoc """
  Deletes a deleted project's space, with its notebooks, from its fleet's
  notebook hub: the space the project recorded, and any the provisioner made
  for it and tagged `keyfleet/<project name>` (`Regents.Keyfleet.Notebooks.Space`).
  Queued in the transaction that deletes the project
  (`Regents.Keyfleet.Projects.Changes.Forget`), once per project. It runs on the
  `notebook_hubs` queue, one run at a time, so a space still being made
  when the project was deleted is made first and found here by its tag. A
  space already gone counts as deleted, so a run that fails part way is
  simply run again. A hub that does not answer is waited for first
  (`Regents.Keyfleet.Notebooks.HubClient.wait_while_away/2`).
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id, :project], period: :infinity, states: :incomplete]

  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.HubClient

  @impl Oban.Worker
  def perform(
        %Oban.Job{args: %{"fleet_id" => fleet_id, "project" => name, "space" => space}} = job
      ) do
    if Notebooks.hub?(fleet_id),
      do: fleet_id |> delete(name, space) |> HubClient.wait_while_away(job),
      else: {:cancel, :no_hub}
  end

  defp delete(fleet_id, name, space) do
    with {:ok, spaces} <- HubClient.projects(fleet_id) do
      fleet_id
      |> ours(spaces, "keyfleet/" <> name)
      |> Enum.concat(List.wrap(space))
      |> Enum.uniq()
      |> Enum.reduce_while(:ok, fn id, :ok -> delete_space(fleet_id, id) end)
    end
  end

  defp delete_space(fleet_id, id) do
    case HubClient.delete_project(fleet_id, id) do
      {:ok, _deleted} -> {:cont, :ok}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp ours(fleet_id, spaces, tag) do
    provisioner = HubClient.provisioner(fleet_id)

    for %{"id" => id, "owner" => ^provisioner, "tags" => tags} <- spaces, tag in tags, do: id
  end
end
