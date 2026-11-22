defmodule RegentsWeb.Keyfleet.AgentTools.Workspace.Answer do
  @moduledoc """
  The workspace's pins as an agent keeps them, the same over its signed
  requests (`RegentsWeb.Keyfleet.AgentGraphController`) and as the Claude
  connector's tools (`RegentsWeb.Keyfleet.AgentTools.Workspace`): pinning a notebook
  in a project's Docs or a file or folder of its code (`:pin`), and taking
  off a pin its person or one of their agents put there (`:unpin`). Each
  answer is `{status, body, nil}`; `params` is the signed request's JSON, its
  body with the fleet's id from its address.

  A pin names what the project holds now, titled as the workspace page
  titles it, and is the agent's person's, so a person's pins and their
  agents' are one set.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Code, Fleets, Graph, Notebooks, Projects}
  alias Regents.Keyfleet.Notebooks.HubClient
  alias RegentsWeb.Keyfleet.WorkspaceRefusal

  @places %{"docs" => :docs, "code" => :code}

  @doc "Answers `op` for `actor`; nothing here waits, so the waiter is unused."
  @spec answer(atom(), map(), Agent.t(), term()) :: {pos_integer(), map(), nil}
  def answer(:pin, %{"fleet_id" => fleet_id, "project" => name} = params, actor, _waiter) do
    place = Map.fetch!(@places, params["place"])

    with {:ok, %{}} <- Fleets.get_fleet(fleet_id, actor: %System{}),
         {:ok, projects} <- Projects.projects(fleet_id, actor: actor),
         {:ok, project} <- shown(projects, name),
         {:ok, title, folder?} <- pinned(fleet_id, project, place, params["target"]),
         {:ok, pin} <-
           Graph.pin(
             %{
               fleet_id: fleet_id,
               project: name,
               place: place,
               target: params["target"],
               title: title,
               folder?: folder?
             },
             actor: actor
           ) do
      {200, %{pin: pin_json(pin)}, nil}
    else
      {:ok, nil} -> refusal(404, "fleet_unknown")
      :unknown -> refusal(404, "project_unknown")
      :not_there -> refusal(404, "pin_target_unknown")
      {:unreadable, :docs} -> refusal(503, "notebooks_unavailable")
      {:unreadable, :code} -> refusal(503, "code_unavailable")
      {:error, error} -> refuse(error, fleet_id)
    end
  end

  # Lifting a pin, which only its pinner does, as on the page.
  def answer(:unpin, %{"fleet_id" => fleet_id, "project" => name} = params, actor, _waiter) do
    place = Map.fetch!(@places, params["place"])

    with {:ok, %{}} <- Fleets.get_fleet(fleet_id, actor: %System{}),
         {:ok, pins} <- Graph.pins(fleet_id, place, name, actor: actor),
         {:pin, %{} = pin} <- {:pin, Enum.find(pins, &(&1.target == params["target"]))},
         {:yours, true} <- {:yours, pin.human_account_id == actor.human_account_id},
         :ok <- Graph.unpin(pin, actor: actor) do
      {200, %{unpinned: pin_json(pin)}, nil}
    else
      {:ok, nil} -> refusal(404, "fleet_unknown")
      {:pin, nil} -> refusal(404, "pin_unknown")
      {:yours, false} -> refusal(403, "pin_not_yours")
      {:error, error} -> refuse(error, fleet_id)
    end
  end

  # What a pin names, as the project holds it now: a notebook by its id,
  # titled as the hub titles it, or a file or folder by its path, titled by
  # that path.
  defp pinned(fleet_id, %{hub_project_id: space}, :docs, id) when is_binary(space) do
    if Notebooks.hub?(fleet_id) do
      case HubClient.notebook(fleet_id, space, id) do
        {:ok, %{"title" => title}} -> {:ok, title, false}
        {:ok, nil} -> :not_there
        {:error, _error} -> {:unreadable, :docs}
      end
    else
      :not_there
    end
  end

  defp pinned(_fleet_id, _project, :docs, _id), do: :not_there

  defp pinned(_fleet_id, %{repository: repository}, :code, path) do
    {parents, [name]} = path |> String.split("/") |> Enum.split(-1)

    if Enum.any?([name | parents], &(&1 in ["", ".", ".."])),
      do: :not_there,
      else: in_folder(repository, Enum.join(parents, "/"), name, path)
  end

  defp in_folder(repository, folder, name, path) do
    case Code.folder(repository, folder) do
      {:ok, entries} ->
        case Enum.find(entries, &(&1.name == name)) do
          nil -> :not_there
          entry -> {:ok, path, entry.folder?}
        end

      {:error, _error} ->
        {:unreadable, :code}
    end
  end

  defp shown(projects, name) do
    case Enum.find(projects, &(&1.name == name)) do
      nil -> :unknown
      project -> {:ok, project}
    end
  end

  defp pin_json(pin),
    do: %{
      project: pin.project,
      place: pin.place,
      target: pin.target,
      title: pin.title,
      folder: pin.folder?
    }

  # A write the workspace refused names its refusal, a restricted Key's
  # included. Otherwise only the fleet's members pin in its workspace, and who
  # they are can't be read while the fleet's key ownership is not fresh; any
  # other invalid input is the request's, and anything else is a fault,
  # raised as one.
  defp refuse(%{errors: errors} = error, fleet_id) do
    case Enum.find_value(errors, &WorkspaceRefusal.for_error/1) do
      {status, body} -> {status, body, nil}
      nil -> unnamed(error, fleet_id)
    end
  end

  defp unnamed(%Ash.Error.Forbidden{}, fleet_id) do
    if Regents.Keyfleet.Chain.fresh?(fleet_id),
      do: refusal(403, "workspace_members_only"),
      else: refusal(503, "ownership_refreshing")
  end

  defp unnamed(%Ash.Error.Invalid{}, _fleet_id), do: refusal(422, "invalid_request")
  defp unnamed(error, _fleet_id), do: raise(error)

  defp refusal(status, code) do
    {status, body} = WorkspaceRefusal.refusal(status, code)
    {status, body, nil}
  end
end
