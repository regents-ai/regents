defmodule Regents.Keyfleet.Projects do
  @moduledoc """
  The projects inside each fleet. A project gives one piece of the fleet's
  work its own board, its own space in the fleet's notebook hub and its own
  repository in the code store. Every fleet has `general`, archived and held
  by Key 3 (Key 329 in Regents Club), which holds the starting goals, the fleet's first notebook space
  and its first repository.

  Every fleet also shares projects that no Key holds, always active:
  `understanding`, the fleet's notes on working together, and, in every fleet
  but Regents Club, the `scratchpad`, with a notebook for each Key
  (`bootstrap_shared!/1`).

  Every other project is held by one of the fleet's Keys and is active, archived or
  deleted. A Key holds at most one active project and five archived ones; it
  starts, archives, takes over and deletes them as `Regents.Keyfleet.Projects.Project`
  says. New work goes into any active project, whoever holds it; an archived
  one takes no writes until a Key takes it over.

  Every member of the fleet sees every project that is not deleted and works
  in any active one: membership is the fleet's, never a project's. Visitors
  see each project's title and the titles of the goals inside it, and
  nothing else of the workspace, unless the Key holding a project shows its
  page's work to everyone.

  A Key also makes public what it made (`Regents.Keyfleet.Projects.Publication`), for
  the workspace's Public place, which anyone reads.

  Acting as a Key is the same rule as every workspace write
  (`Regents.Keyfleet.Graph.Checks.KeyActor`). A project is never renamed or moved,
  and a deleted project's name is never used again.
  """
  use Ash.Domain

  alias Regents.Keyfleet.Projects.Errors.ClosedError
  alias Regents.Keyfleet.Projects.Project

  require Ash.Query

  resources do
    resource Regents.Keyfleet.Projects.Project do
      define :projects, action: :in_fleet, args: [:fleet_id]
      define :project_titles, action: :titles, args: [:fleet_id]

      define :projects_started_before,
        action: :started_before,
        args: [:fleet_id, :before_at, :before_name, :limit]

      define :project, action: :named, args: [:fleet_id, :name], not_found_error?: false

      define :project_of_repository,
        action: :by_repository,
        args: [:repository],
        not_found_error?: false

      define :locked_project_of_repository, action: :locked_by_repository, args: [:repository]

      define :locked_project,
        action: :locked_named,
        args: [:fleet_id, :name],
        not_found_error?: false

      define :start_project, action: :start, args: [:fleet_id, :as_key, :name, :title]
      define :archive_project, action: :archive, args: [:fleet_id, :as_key]
      define :take_over_project, action: :take_over, args: [:fleet_id, :as_key, :name]
      define :delete_project, action: :delete, args: [:fleet_id, :as_key, :name]

      define :show_project,
        action: :show,
        args: [:fleet_id, :as_key, :name, :shown_to_everyone]

      define :describe_project,
        action: :describe,
        args: [:fleet_id, :as_key, :name, :description]

      define :project_page, action: :page, args: [:fleet_id, :name], not_found_error?: false
      define :record_space, action: :record_space, args: [:hub_project_id]
    end

    resource Regents.Keyfleet.Projects.Publication do
      define :publications, action: :in_fleet, args: [:fleet_id, {:optional, :project}]

      define :publish_posts,
        action: :publish_posts,
        args: [:fleet_id, :as_key, :project, :room, :from_seq, :to_seq]

      define :publish_item, action: :publish_item, args: [:fleet_id, :as_key, :item]

      define :item_publication,
        action: :of_item,
        args: [:fleet_id, :item],
        not_found_error?: false

      define :publish_page, action: :publish_page, args: [:fleet_id, :as_key, :page]

      define :page_publication,
        action: :of_page,
        args: [:fleet_id, :page],
        not_found_error?: false

      define :publish_commit,
        action: :publish_commit,
        args: [:fleet_id, :as_key, :project, :commit_hash]

      define :commit_publication,
        action: :of_commit,
        args: [:fleet_id, :project, :commit_hash],
        not_found_error?: false

      define :withdraw_publication, action: :withdraw, args: [:fleet_id, :as_key, :id]
    end
  end

  @doc "The project every fleet has, which holds the starting goals."
  def general, do: "general"

  @doc """
  Gives each of these fleets its `general`, archived and held by Key 3 (Key
  329 in Regents Club), unless it has it already; a fleet that has it keeps it as it is.
  """
  def bootstrap_general!(fleet_ids) do
    Ash.bulk_create!(
      Enum.map(fleet_ids, &%{fleet_id: &1}),
      Regents.Keyfleet.Projects.Project,
      :general,
      actor: %Regents.Account.Actors.System{},
      return_errors?: true,
      stop_on_error?: true,
      transaction: :all,
      sorted?: true
    )

    :ok
  end

  @doc """
  Gives each of these fleets the projects it shares (`Project.shared_names/1`),
  active and held by no Key, unless it has them already: `understanding`,
  titled after the fleet, and the `scratchpad`, titled "Append-only
  scratchpad". A fleet that has them keeps them, their titles made canonical
  again. One it no longer shares goes at its next roster run (`unshare!/1`).
  """
  def bootstrap_shared!(fleets) do
    Ash.bulk_create!(
      for(
        fleet <- fleets,
        name <- Project.shared_names(fleet.id),
        do: %{fleet_id: fleet.id, name: name, title: shared_title(name, fleet)}
      ),
      Project,
      :shared,
      actor: %Regents.Account.Actors.System{},
      return_errors?: true,
      stop_on_error?: true,
      transaction: :all,
      sorted?: true
    )

    :ok
  end

  @doc """
  Deletes each shared project the fleet no longer shares
  (`Project.shared_names/1`), as a deleted project goes: its space and
  repository go by the jobs it queues (`Regents.Keyfleet.Projects.Changes.Forget`).
  The fleet's roster run calls it (`Regents.Keyfleet.Notebooks.Roster`); a fleet
  that has none changes nothing.
  """
  def unshare!(fleet_id) do
    Project
    |> Ash.Query.for_read(:in_fleet, %{fleet_id: fleet_id},
      actor: %Regents.Account.Actors.System{}
    )
    |> Ash.Query.filter(is_nil(key) and name not in ^Project.shared_names(fleet_id))
    |> Ash.bulk_update!(:unshared, %{},
      actor: %Regents.Account.Actors.System{},
      strategy: [:stream],
      allow_stream_with: :full_read,
      return_errors?: true
    )

    :ok
  end

  defp shared_title("scratchpad", _fleet), do: "Append-only scratchpad"

  defp shared_title("understanding", fleet),
    do: "Keyfleet #{fleet.name} Collaborative Understanding"

  @doc """
  The fleet's project `name` as `{:ok, project}` while it is active, so it
  takes new work; else `{:error, %ClosedError{}}` naming the fleet's active
  projects, for an archived project or a name the fleet has none by.
  """
  def open(fleet_id, name) do
    projects = projects!(fleet_id, actor: %Regents.Account.Actors.System{})
    active = for %{state: :active, name: active} <- projects, do: active

    case Enum.find(projects, &(&1.name == name)) do
      %{state: :active} = project ->
        {:ok, project}

      found ->
        code = if found, do: :project_archived, else: :project_unknown
        {:error, ClosedError.exception(code: code, project: name, active: active)}
    end
  end

  @doc """
  The fleet's projects for a member choosing where work goes: the active
  ones first, oldest first, then the archived ones.
  """
  def by_state(fleet_id, opts) do
    with {:ok, projects} <- projects(fleet_id, opts) do
      {:ok, Enum.sort_by(projects, &(&1.state != :active))}
    end
  end
end
