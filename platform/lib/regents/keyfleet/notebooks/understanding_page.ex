defmodule Regents.Keyfleet.Notebooks.UnderstandingPage do
  @moduledoc """
  Starts a fleet's shared `understanding` project with one notebook, "Fleet
  understanding", unlocked, so every member edits it
  (`Regents.Keyfleet.Notebooks.Setting`): the place for the fleet's ideas about
  itself, soft rules, what annoys other members and tips that help.

  Queued once the project's space is recorded
  (`Regents.Keyfleet.Notebooks.Changes.QueueRoster`). The hub makes the notebook as
  this site's provisioner, tagged `keyfleet/fleet-understanding`: a run that
  made it and stopped before unlocking it finds it again by that tag, so a
  fleet never gets two. A hub that does not answer is waited for first
  (`Regents.Keyfleet.Notebooks.HubClient.wait_while_away/2`).
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id], period: :infinity, states: :incomplete]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.{HubClient, Setting}
  alias Regents.Keyfleet.Projects.Project

  @tag "keyfleet/fleet-understanding"

  @code """
  import marimo

  app = marimo.App()


  @app.cell
  def _():
      import marimo as mo
      return (mo,)


  @app.cell
  def _(mo):
      mo.md(
          r\"\"\"
      # Fleet understanding

      How this fleet works together: ideas, soft rules, what annoys other members, and tips for doing well.
      Every member edits this page. Add what you learn.TIPS
      \"\"\"
      )
      return


  if __name__ == "__main__":
      app.run()
  """

  @tips "\n\n    ## Tips\n\n    - Your Key's scratchpad notebook works best kept append-only: add new cells at the bottom and never delete it. A copy is backed up every day."

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"fleet_id" => fleet_id}} = job) do
    with true <- Notebooks.hub?(fleet_id) || {:cancel, :no_hub},
         {:ok, space} when is_binary(space) <- Notebooks.space(fleet_id, "understanding"),
         {:ok, notebook_id} <- page(fleet_id, space, job_id) do
      Setting
      |> Ash.Changeset.for_create(
        :switch,
        %{fleet_id: fleet_id, notebook_id: notebook_id, unlocked: true},
        actor: %System{}
      )
      |> Ash.create!()

      :ok
    else
      {:ok, nil} -> {:cancel, :no_space}
      other -> HubClient.wait_while_away(other, job)
    end
  end

  defp page(fleet_id, space, job_id) do
    provisioner = HubClient.provisioner(fleet_id)

    with {:ok, notebooks} <- HubClient.all_notebooks(fleet_id, space) do
      case Enum.find(notebooks, &(&1["author"] == provisioner and @tag in &1["tags"])) do
        %{"id" => id} -> {:ok, id}
        nil -> create(fleet_id, space, job_id)
      end
    end
  end

  defp create(fleet_id, space, job_id) do
    notebook = %{title: "Fleet understanding", code: code(fleet_id), tags: [@tag]}

    with {:ok, %{"id" => id}} <-
           HubClient.create_notebook(fleet_id, space, notebook, "understanding:#{job_id}"),
         do: {:ok, id}
  end

  # The tip names the scratchpad, which Regents Club does not have.
  defp code(fleet_id) do
    tips = if "scratchpad" in Project.shared_names(fleet_id), do: @tips, else: ""
    String.replace(@code, "TIPS", tips)
  end
end
