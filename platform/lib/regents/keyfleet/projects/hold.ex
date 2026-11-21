defmodule Regents.Keyfleet.Projects.Hold do
  @moduledoc """
  Starts, archives, takes over and deletes a project as one of the fleet's
  Keys, shows its page's work to everyone or to members only, and describes
  it (`Regents.Keyfleet.Projects.Project`). The actor acts as the Key the same way
  a workspace write does (`Regents.Keyfleet.Graph.Checks.KeyActor`), read in the
  one transaction in which the step is checked against the projects the Key
  holds and made, an agent's pairing held until it commits. A refusal says
  why in words that name the project (`Regents.Keyfleet.Projects.Errors.HoldError`).

  The database keeps each rule even when two steps run at once: one active
  project per Key is a unique index, and each change of state is made only
  from the state it was checked in, so of two steps on one project the
  second finds it changed and is refused. A second start or take-over the
  index refuses, from a double press, is told as the check tells it
  (`active_held`), in the index's own words.

  A project the whole fleet shares, held by no Key, is never archived, taken
  over, deleted, shown to everyone or described: no Key holds it as its
  active project, and it is never archived.

  Once a delete is kept, everyone's admission to the fleet's notebooks ends,
  so their next request is let in to the spaces left, without the deleted
  project's.
  """
  use Ash.Resource.Actions.Implementation

  alias Ash.Error.Changes.InvalidAttribute
  alias Regents.Keyfleet.Graph.Checks.KeyActor
  alias Regents.Keyfleet.Notebooks
  alias Regents.Keyfleet.Projects.Errors.{HoldError, NameTakenError, UnknownProjectError}
  alias Regents.Keyfleet.Projects.Project

  @system %Regents.Account.Actors.System{}
  # The unique index behind the identity `one_active_per_key`.
  @one_active "projects_one_active_per_key_index"

  @impl true
  def run(input, opts, %{actor: actor}) do
    %{fleet_id: fleet_id, as_key: key} = input.arguments
    within = Application.fetch_env!(:regents, :keyfleet_graph)[:check_timeout]
    step = Keyword.fetch!(opts, :step)

    held_step = fn ->
      with {:ok, _command} <- KeyActor.held_command(actor, fleet_id, key, nil, within),
           do: step(step, fleet_id, key, input.arguments)
    end

    with {:ok, project} <- Ash.transact(Project, held_step) do
      if step == :delete, do: Notebooks.end_access(fleet_id)
      {:ok, project}
    end
  end

  defp step(:start, fleet_id, key, %{name: name, title: title}) do
    with :ok <- none_active(fleet_id, key),
         :ok <- name_free(fleet_id, name) do
      Project
      |> Ash.Changeset.for_create(
        :create,
        %{fleet_id: fleet_id, name: name, title: title, key: key},
        actor: @system
      )
      |> Ash.create()
      |> unwrap()
    end
  end

  defp step(:archive, fleet_id, key, _arguments) do
    with {:ok, project} <- active(fleet_id, key),
         :ok <- archive_room(fleet_id, key) do
      project
      |> Ash.Changeset.for_update(:archived, %{}, actor: @system)
      |> Ash.update()
      |> unwrap()
    end
  end

  defp step(:take_over, fleet_id, key, %{name: name}) do
    with :ok <- none_active(fleet_id, key),
         {:ok, project} <- named(fleet_id, name),
         :ok <- archived(project, "Only an archived project can be taken over.") do
      project
      |> Ash.Changeset.for_update(:taken_over, %{key: key}, actor: @system)
      |> Ash.update()
      |> unwrap()
    end
  end

  defp step(:delete, fleet_id, key, %{name: name}) do
    with {:ok, project} <- named(fleet_id, name),
         :ok <- archived(project, "Archive it before deleting it."),
         :ok <- creator(project, key) do
      project
      |> Ash.Changeset.for_update(:deleted, %{key: key}, actor: @system)
      |> Ash.update()
      |> unwrap()
    end
  end

  defp step(:show, fleet_id, key, %{name: name, shown_to_everyone: shown}) do
    with {:ok, project} <- named(fleet_id, name),
         :ok <- holder(project, key, "choose who sees its work") do
      project
      |> Ash.Changeset.for_update(:shown, %{shown_to_everyone: shown, key: key}, actor: @system)
      |> Ash.update()
      |> unwrap()
    end
  end

  defp step(:describe, fleet_id, key, %{name: name} = arguments) do
    with {:ok, project} <- named(fleet_id, name),
         :ok <- holder(project, key, "describe it") do
      project
      |> Ash.Changeset.for_update(
        :described,
        %{description: arguments[:description], key: key},
        actor: @system
      )
      |> Ash.update()
      |> unwrap()
    end
  end

  defp none_active(fleet_id, key) do
    case held(fleet_id, key, :active) do
      [] ->
        :ok

      [project] ->
        refuse(
          :active_held,
          project,
          "Key #{key} is working on #{project.title}. Archive it first."
        )
    end
  end

  defp active(fleet_id, key) do
    case held(fleet_id, key, :active) do
      [project] -> {:ok, project}
      [] -> refuse(:no_active, nil, "Key #{key} has no active project to archive.")
    end
  end

  defp archive_room(fleet_id, key) do
    if length(held(fleet_id, key, :archived)) < Project.archived_most(),
      do: :ok,
      else:
        refuse(
          :archive_full,
          nil,
          "Key #{key} holds five archived projects. Delete one it started, or another Key can take one over."
        )
  end

  defp name_free(fleet_id, name) do
    case Ash.read_one!(read(:ever_named, %{fleet_id: fleet_id, name: name})) do
      nil -> :ok
      _project -> {:error, NameTakenError.exception(fleet_id: fleet_id, name: name)}
    end
  end

  defp named(fleet_id, name) do
    case Ash.read_one!(read(:named, %{fleet_id: fleet_id, name: name})) do
      nil -> {:error, UnknownProjectError.exception(fleet_id: fleet_id, project: name)}
      project -> {:ok, project}
    end
  end

  defp archived(%{state: :archived}, _why), do: :ok

  defp archived(%{key: nil} = project, _why),
    do: refuse(:shared, project, "#{project.title} belongs to the whole fleet.")

  defp archived(project, why),
    do:
      refuse(:not_archived, project, "#{project.title} is active with Key #{project.key}. #{why}")

  defp holder(%{key: key}, key, _what), do: :ok

  defp holder(%{key: nil} = project, _key, _what),
    do: refuse(:shared, project, "#{project.title} belongs to the whole fleet.")

  defp holder(project, _key, what),
    do:
      refuse(
        :not_holder,
        project,
        "#{project.title} is held by Key #{project.key}. Only that Key can #{what}."
      )

  # Taking a project over never makes a Key the one that started it.
  defp creator(%{created_by_key: key}, key), do: :ok

  defp creator(project, _key),
    do:
      refuse(
        :not_creator,
        project,
        "#{project.title} was started by Key #{project.created_by_key}. Only that Key can delete it."
      )

  defp held(fleet_id, key, state),
    do: Ash.read!(read(:held, %{fleet_id: fleet_id, key: key, state: state}))

  defp read(action, arguments), do: Ash.Query.for_read(Project, action, arguments, actor: @system)

  defp refuse(code, project, words),
    do: {:error, HoldError.exception(code: code, words: words, project: project && project.name)}

  defp unwrap({:ok, project}), do: project

  defp unwrap({:error, %Ash.Error.Invalid{errors: errors} = error}) do
    case Enum.find(errors, &one_active?/1) do
      %InvalidAttribute{message: words} -> refuse(:active_held, nil, words)
      nil -> {:error, error}
    end
  end

  defp unwrap({:error, error}), do: {:error, error}

  defp one_active?(%InvalidAttribute{private_vars: vars}), do: vars[:constraint] == @one_active
  defp one_active?(_error), do: false
end
