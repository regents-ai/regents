defmodule Regents.Keyfleet.Notebooks.Scratchpads do
  @moduledoc """
  Gives every Key of a fleet its own notebook, "Key N", in the fleet's shared
  `scratchpad` project, kept as that Key's (`Regents.Keyfleet.Notebooks.Setting`):
  whoever acts as the Key is its creator, and it stays with the Key's number
  when the Key changes hands. Every member of the fleet reads it.

  Each roster run queues it (`Regents.Keyfleet.Notebooks.Roster`), so a Key sold, a
  scratchpad space just made or a scratchpad deleted gets its notebook within
  ten minutes: a kept scratchpad the hub no longer has is forgotten first. The hub makes each notebook as this site's provisioner, tagged
  `keyfleet/key-<N>`: a run that made one and stopped before keeping it finds
  it again by that tag, so a Key never gets two. Runs go one at a time on the
  `notebook_hubs` queue, and one run per fleet waits at a time.
  """
  use Oban.Worker,
    queue: :keyfleet_notebook_hubs,
    max_attempts: 20,
    unique: [keys: [:fleet_id], period: :infinity, states: [:available, :retryable]]

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Notebooks.{HubClient, Setting}

  require Ash.Query

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"fleet_id" => fleet_id}}) do
    with true <- Notebooks.hub?(fleet_id) || {:cancel, :no_hub},
         {:ok, space} when is_binary(space) <- Notebooks.space(fleet_id, "scratchpad"),
         {:ok, notebooks} <- HubClient.all_notebooks(fleet_id, space) do
      case keys(fleet_id) -- kept(fleet_id, notebooks) do
        [] -> :ok
        missing -> make(fleet_id, space, notebooks, missing, job_id)
      end
    else
      # The roster run makes the space, and runs this again once it has.
      {:ok, nil} -> :ok
      other -> other
    end
  end

  # Every Key of the fleet sold so far.
  defp keys(fleet_id) do
    Regents.Keyfleet.Keys.KeyAttachment
    |> Ash.Query.for_read(:current_in_fleet, %{fleet_id: fleet_id})
    |> Ash.stream!(actor: %System{}, batch_size: 100)
    |> Enum.map(& &1.token_id)
  end

  # The Keys whose scratchpad the hub still has; the others are forgotten.
  defp kept(fleet_id, notebooks) do
    present = MapSet.new(notebooks, & &1["id"])

    {kept, gone} =
      Setting
      |> Ash.Query.for_read(:scratchpads, %{fleet_id: fleet_id}, actor: %System{})
      |> Ash.read!()
      |> Enum.split_with(&MapSet.member?(present, &1.notebook_id))

    gone_ids = Enum.map(gone, & &1.id)

    Setting
    |> Ash.Query.filter(id in ^gone_ids)
    |> Ash.bulk_destroy!(:forget, %{}, actor: %System{}, strategy: :atomic, notify?: false)

    Enum.map(kept, & &1.key)
  end

  defp make(fleet_id, space, notebooks, missing, job_id) do
    provisioner = HubClient.provisioner(fleet_id)

    made =
      for %{"author" => ^provisioner, "id" => id, "tags" => tags} <- notebooks,
          "keyfleet/key-" <> key <- tags,
          into: %{},
          do: {key, id}

    Enum.reduce_while(missing, :ok, fn key, :ok ->
      case made[Integer.to_string(key)] || create(fleet_id, space, key, job_id) do
        {:error, error} -> {:halt, {:error, error}}
        id -> {:cont, keep(fleet_id, id, key)}
      end
    end)
  end

  defp create(fleet_id, space, key, job_id) do
    notebook = %{title: "Key #{key}", code: code(key), tags: ["keyfleet/key-#{key}"]}

    case HubClient.create_notebook(fleet_id, space, notebook, "scratchpad:#{job_id}:#{key}") do
      {:ok, %{"id" => id}} -> id
      {:error, error} -> {:error, error}
    end
  end

  defp keep(fleet_id, notebook_id, key) do
    Setting
    |> Ash.Changeset.for_create(
      :scratchpad,
      %{fleet_id: fleet_id, notebook_id: notebook_id, key: key},
      actor: %System{}
    )
    |> Ash.create!()

    :ok
  end

  defp code(key) do
    """
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
        # Key #{key} scratchpad

        Whoever acts as Key #{key} writes here, and every member of the fleet reads it.
        Add new cells at the bottom and keep what is above. A copy is backed up every day.
        \"\"\"
        )
        return


    if __name__ == "__main__":
        app.run()
    """
  end
end
