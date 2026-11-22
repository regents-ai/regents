defmodule RegentsWeb.Keyfleet.AgentTools.Workspace.Read do
  @moduledoc """
  Runs one of the workspace's reads for `RegentsWeb.Keyfleet.AgentTools.Workspace`,
  as the calling agent, and answers what its signed request answers.
  """
  use Ash.Resource.Actions.Implementation

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.{Code, Fleets, Graph, Notebooks, Projects, Rooms}

  alias Regents.Keyfleet.Graph.Errors.{
    ComingSoonFleetError,
    MembersOnlyError,
    UnavailableError,
    UnknownFleetError
  }

  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Projects.Errors.UnknownProjectError
  alias RegentsWeb.Endpoint
  alias RegentsWeb.Keyfleet.{RoomJSON, WorkspacePage, WorkspaceRefusal}

  # As many goals as the workspace reads in one page.
  @board_goals 24
  # As many of the tasks waiting longest for review as the Project lists.
  @board_reviews 6

  @parts ~w(owner_key relations linked url discussion commit rerun_check agents)a

  @impl true
  def run(input, opts, context) do
    fleet_id = input.arguments.fleet_id

    opts[:read]
    |> read(input.arguments, Ash.Context.to_opts(context))
    |> answer(fleet_id)
  end

  # The workspace's graph as its Graph view draws it: the items, the links
  # between them and the Keys that own them, with the page's filters, each
  # item with its page's address.
  defp read(:view, %{fleet_id: fleet_id} = args, opts) do
    filter = Map.take(args, [:project, :type, :owner_key, :goal, :archived])

    with :ok <- known_fleet(fleet_id),
         {:ok, projects} <- Projects.projects(fleet_id, opts),
         {:ok, _shown} <- shown(projects, args[:project], fleet_id),
         {:ok, graph} <- Graph.workspace_graph(fleet_id, filter, opts) do
      {:ok,
       Map.update!(graph, :nodes, fn nodes -> Enum.map(nodes, &graph_node(&1, fleet_id)) end)}
    end
  end

  # One item as its page in the workspace shows it, in one read: the item,
  # its links and the items at their other ends, its page's address, the posts
  # its discussion names and, for a task, the commit to clone and what its
  # rerun is missing. `fields` names the parts besides the item to answer;
  # the posts its discussion names are read only when it names them.
  defp read(:show, %{fleet_id: fleet_id, id: id} = args, opts) do
    parts = parts(args[:fields])

    with {:ok, read} <-
           Graph.get_object(fleet_id, id, %{relations_after: args.relations_after}, opts) do
      {:ok,
       read
       |> Map.merge(around(read.object, fleet_id, opts[:actor], parts))
       |> Map.take(parts)}
    end
  end

  defp read(:changes, %{fleet_id: fleet_id} = args, opts),
    do:
      Graph.list_changes(
        fleet_id,
        Map.take(args, [:after_seq, :limit, :project, :object, :max_bytes]),
        opts
      )

  defp read(:packet, %{fleet_id: fleet_id} = args, opts),
    do: Graph.workspace_packet(fleet_id, Map.take(args, [:project, :ids, :max_bytes]), opts)

  # What the workspace's pages keep at hand, the whole fleet's or one
  # project's: how many goals and tasks stand where, its newest goals and the
  # tasks that have waited longest for review, as its Project shows them, and
  # what its members pinned in its Docs and its Code.
  defp read(:board, %{fleet_id: fleet_id} = args, opts) do
    project = args[:project]

    with :ok <- known_fleet(fleet_id),
         {:ok, projects} <- Projects.projects(fleet_id, opts),
         {:ok, shown} <- shown(projects, project, fleet_id),
         {:ok, goals} <-
           Graph.workspace_cards(
             fleet_id,
             %{type: "goal", project: project},
             Keyword.put(opts, :page, limit: @board_goals)
           ),
         {:ok, counts} <- Graph.tally(fleet_id, project, opts),
         {:ok, awaiting} <-
           Graph.awaiting_review(
             fleet_id,
             %{project: project},
             [query: [limit: @board_reviews]] ++ opts
           ),
         {:ok, notebooks} <- Graph.pins(fleet_id, :docs, project, opts),
         {:ok, code} <- Graph.pins(fleet_id, :code, project, opts) do
      {:ok,
       %{
         counts: counts,
         goals: Enum.map(goals.results, &goal(&1, fleet_id)),
         more_goals: goals.more?,
         awaiting_review: Enum.map(awaiting, &awaiting(&1, fleet_id)),
         pinned_notebooks:
           for pin <- notebooks do
             space = if Notebooks.hub?(fleet_id), do: shown[pin.project].hub_project_id

             %{
               project: pin.project,
               notebook_id: pin.target,
               title: pin.title,
               notebook_url: space && Notebooks.notebook_url(fleet_id, space, pin.target)
             }
           end,
         pinned_code:
           for pin <- code do
             repository = shown[pin.project].repository

             %{
               project: pin.project,
               path: pin.target,
               title: pin.title,
               folder: pin.folder?,
               url: Endpoint.url() <> Code.files_path(fleet_id, repository, pin.target)
             }
           end
       }}
    end
  end

  @doc """
  `:ok` for a fleet in the catalog that has opened; otherwise the error its
  workspace's reads answer, as `answer/2` takes it.
  """
  def known_fleet(fleet_id) do
    case Fleets.get_fleet(fleet_id, actor: %System{}) do
      {:ok, nil} -> {:error, UnknownFleetError.exception(fleet_id: fleet_id)}
      {:ok, fleet} -> opened(fleet_id, fleet)
      {:error, error} -> {:error, error}
    end
  end

  # A coming-soon fleet has no workspace until it opens.
  defp opened(fleet_id, fleet) do
    if Fleets.coming_soon?(fleet_id, fleet),
      do: {:error, ComingSoonFleetError.exception(fleet_id: fleet_id)},
      else: :ok
  end

  @doc """
  A read's result as the workspace's reads answer it: only the fleet's
  members read its workspace, and who they are can't be read while the
  fleet's key ownership is not fresh.
  """
  def answer({:ok, result}, _fleet_id), do: {:ok, result}

  def answer({:error, %Ash.Error.Forbidden{} = error}, fleet_id) do
    cond do
      Enum.any?(error.errors, &WorkspaceRefusal.for_error/1) ->
        {:error, error}

      Regents.Keyfleet.Chain.fresh?(fleet_id) ->
        {:error, MembersOnlyError.exception(fleet_id: fleet_id)}

      true ->
        {:error, OwnershipRefreshingError.exception(fleet_id: fleet_id)}
    end
  end

  def answer({:error, %Ash.Error.Unknown{errors: errors} = error}, fleet_id) do
    if Enum.any?(errors, &WorkspaceRefusal.for_error/1),
      do: {:error, error},
      else: unreadable(error, fleet_id)
  end

  def answer({:error, error}, _fleet_id), do: {:error, error}

  # A read that failed some other way, such as the database not answering.
  # Nothing was written, so the workspace is answered as unavailable, and the
  # failure is saved with the site's errors beside the answer, which never
  # waits on the save, so one that keeps failing is seen at /admin/errors.
  defp unreadable(error, fleet_id) do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    context = ErrorTracker.get_context()

    Task.Supervisor.start_child(Regents.Keyfleet.ErrorSaves, fn ->
      Regents.Alert.save(error, Enum.drop(stacktrace, 1), context)
    end)

    {:error, UnavailableError.exception(fleet_id: fleet_id)}
  end

  # The item and how far the workspace had read are always answered; a page
  # of links comes with the place to read on from.
  defp parts(nil), do: [:object, :watermark, :relations_next_cursor | @parts]

  defp parts(fields) do
    named = fields |> String.split(",") |> Enum.map(&String.to_existing_atom/1)

    [:object, :watermark | named] ++
      if(:relations in named, do: [:relations_next_cursor], else: [])
  end

  defp around(object, fleet_id, actor, parts) do
    %{
      url: fn -> Endpoint.url() <> WorkspacePage.item_path(fleet_id, object.id) end,
      discussion: fn -> discussion(object.data["discussion"], fleet_id, actor) end,
      commit: fn -> commit(object.data["commit_ref"], fleet_id) end
    }
    |> Map.take(parts)
    |> Map.new(fn {part, read} -> {part, read.()} end)
  end

  # Each post the item's discussion names, as a room read answers it: nil for
  # one the agent can't read there, such as a post by a Key it muted, or a
  # place the room has no post at.
  defp discussion(links, fleet_id, actor) when is_list(links) and links != [] do
    muted = Rooms.muted_keys!(fleet_id, actor)

    for %{"room" => room, "seq" => seq} <- links do
      %{room: room, seq: seq, post: post(fleet_id, room, seq, muted, actor)}
    end
  end

  defp discussion(_links, _fleet_id, _actor), do: []

  defp post(fleet_id, room, seq, muted, actor) do
    case Rooms.read_messages(fleet_id, room, %{after_seq: seq - 1, limit: 1}, actor: actor) do
      {:ok, [%{seq: ^seq} = message]} ->
        case Rooms.unmuted([message], muted) do
          [shown] -> RoomJSON.message(shown)
          [] -> nil
        end

      _other ->
        nil
    end
  end

  # A commit of one of the fleet's own repositories, with the address its
  # agent clones it from.
  defp commit(uri, fleet_id) do
    with {repository, hash} <- WorkspacePage.fleet_commit(uri, fleet_id) do
      %{repository: repository, hash: hash, clone_url: Code.agent_clone_url(repository)}
    end
  end

  defp graph_node(node, fleet_id),
    do: Map.put(node, :url, Endpoint.url() <> WorkspacePage.item_path(fleet_id, node.id))

  defp goal(object, fleet_id) do
    %{
      id: object.id,
      project: object.project,
      title: object.title,
      status: object.card["status"],
      starting: is_integer(object.sys["starting"]),
      joined: length(Map.get(object.sys, "joined", [])),
      changed_at: object.changed_at,
      url: Endpoint.url() <> WorkspacePage.item_path(fleet_id, object.id)
    }
  end

  defp awaiting(task, fleet_id) do
    %{
      id: task.id,
      project: task.project,
      title: task.title,
      version: task.version,
      waiting_since: task.changed_at,
      url: Endpoint.url() <> WorkspacePage.item_path(fleet_id, task.id)
    }
  end

  # The projects a board shows, by name: the one asked for, or every one.
  defp shown(projects, nil, _fleet_id), do: {:ok, Map.new(projects, &{&1.name, &1})}

  defp shown(projects, name, fleet_id) do
    case Enum.find(projects, &(&1.name == name)) do
      nil -> {:error, UnknownProjectError.exception(fleet_id: fleet_id, project: name)}
      project -> {:ok, %{name => project}}
    end
  end
end
