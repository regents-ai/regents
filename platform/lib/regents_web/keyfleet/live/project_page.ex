defmodule RegentsWeb.Keyfleet.ProjectPage do
  @moduledoc """
  What a project's page reads, at the fleet's address and the project's name,
  such as `/classic/1/projects/virtual-cell`: the project and the line its
  Key describes it with, its open goals by title as every visitor sees them,
  and, once the Key holding it shows its
  work to everyone (`Regents.Keyfleet.Projects.Project`), its latest work, what it
  produced and the tasks nobody has joined yet or blocked, each by title and the agent
  and Key that made it, with how many there are of each, and under each goal
  the tasks that deliver on it, by title and standing alone. For a reader who
  may read the workspace (`RegentsWeb.Keyfleet.ProjectLive`) each title links to its
  item's page there, and each open or blocked task has a link
  that pairs a visitor's agent and sends it to that task. A project's page
  never shows more than titles and who made them: members read the rest in
  the workspace.

  A name that is no project of the fleet, or a deleted one's, is a page that
  doesn't exist.
  """

  alias Regents.Keyfleet.{Fleets, Graph, Projects}
  alias Regents.Keyfleet.Graph.Object
  alias RegentsWeb.Keyfleet.{ActivityLines, DirectoryMD, WorkspacePage}
  alias RegentsWeb.NotFoundError

  # How many of each part the page lists, newest first.
  @shown 6
  @parts [:goals, :work, :outputs, :open]

  @doc "The page of the project `name` in the fleet `fleet_id`."
  def read(fleet_id, name) do
    case Projects.project_page!(fleet_id, name) do
      nil -> raise NotFoundError
      project -> page(fleet_id, project)
    end
  end

  @doc "A project page's address."
  def path(fleet_id, name), do: Fleets.path(fleet_id) <> "/projects/" <> name

  defp page(fleet_id, project) do
    path = path(fleet_id, project.name)

    %{
      fleet_id: fleet_id,
      fleet_name: Fleets.name(fleet_id),
      fleet_path: Fleets.path(fleet_id),
      name: project.name,
      title: seen(project.title, "A project"),
      description: seen(project.description, nil),
      key: project.key,
      state: project.state,
      shown?: project.shown_to_everyone,
      pair_path: pair_path(path),
      workspace_path: WorkspacePage.place_path(fleet_id, :project, project.name),
      public_path: public_path(fleet_id, project.name),
      goals: if(not project.shown_to_everyone, do: goal_titles(fleet_id, project.name)),
      parts: if(project.shown_to_everyone, do: parts(fleet_id, project.name))
    }
  end

  # The project's Public place, once one of the fleet's Keys has made
  # something public in it.
  defp public_path(fleet_id, name) do
    if Projects.publications!(fleet_id, name, query: [limit: 1]) != [],
      do: WorkspacePage.place_path(fleet_id, :public, name)
  end

  defp goal_titles(fleet_id, name) do
    fleet_id
    |> Graph.open_goals!(%{project: name}, query: [limit: @shown])
    |> Enum.map(&seen(&1.title, "A goal"))
  end

  # Every part from one moment of the read tables, each row with the agent
  # and Key that made it, and under each goal the tasks that deliver on it,
  # by title and standing alone.
  defp parts(fleet_id, name) do
    {:ok, {reads, tasks}} =
      Graph.in_snapshot(fn ->
        reads = Map.new(@parts, &{&1, read_part(fleet_id, name, &1)})
        {goals, _count} = reads.goals

        {reads, goal_tasks(fleet_id, name, Enum.map(goals, & &1.id))}
      end)

    agents =
      reads
      |> Enum.flat_map(fn {_part, {objects, _count}} -> objects end)
      |> Enum.map(&WorkspacePage.creator_wallet(&1.sys))
      |> WorkspacePage.agent_names()

    Map.new(reads, fn {part, {objects, count}} ->
      {part,
       %{
         items:
           for object <- objects do
             fleet_id
             |> item(object, agents)
             |> Map.put(:tasks, Enum.map(Map.get(tasks, object.id, []), &goal_task(fleet_id, &1)))
           end,
         count: count,
         more?: count > @shown
       }}
    end)
  end

  defp goal_tasks(_fleet_id, _name, []), do: %{}

  defp goal_tasks(fleet_id, name, ids) do
    tasks = Graph.shown_goal_tasks!(fleet_id, name, ids, @shown)

    Map.new(ids, fn id ->
      {id, tasks |> Enum.filter(&(id in &1.implemented_goal_ids)) |> Enum.take(@shown)}
    end)
  end

  defp read_part(fleet_id, name, part) do
    query = Ash.Query.for_read(Object, :shown, %{fleet_id: fleet_id, project: name, part: part})
    {query |> Ash.Query.limit(@shown) |> Ash.read!(), Ash.count!(query)}
  end

  defp item(fleet_id, object, agents) do
    {type, _plural} = WorkspacePage.type_name(object.type)
    path = WorkspacePage.item_path(fleet_id, object.id)

    %{
      id: object.id,
      type: type,
      title: seen(object.title, "Untitled"),
      by: made_by(WorkspacePage.created_by(object.sys, agents)),
      standing: standing(object.type, object.standing),
      blocked?: object.type == "task" and object.standing == "blocked",
      path: path,
      pair_path: pair_path(path)
    }
  end

  defp goal_task(fleet_id, task) do
    %{
      id: task.id,
      title: seen(task.title, "Untitled"),
      standing: standing("task", task.standing),
      path: WorkspacePage.item_path(fleet_id, task.id)
    }
  end

  defp made_by({:key, token_id, agent}), do: ActivityLines.key_name(token_id, agent)
  defp made_by(keyfleet), do: keyfleet

  # A link that pairs a visitor's agent and sends it to `path`.
  defp pair_path(path), do: "/pair?to=" <> URI.encode_www_form(path)

  # The graph keeps each status and progress to its choices.
  defp standing(_type, nil), do: nil
  defp standing("goal", status), do: WorkspacePage.choice("status", status)

  defp standing("task", standing)
       when standing in ~w(awaiting_review accepted reproduced disputed),
       do: WorkspacePage.choice("review", standing)

  defp standing("task", progress), do: WorkspacePage.choice("progress", progress)
  defp standing(_type, _standing), do: nil

  defp seen(title, untitled) do
    case (title || "") |> DirectoryMD.visible() |> String.trim() do
      "" -> untitled
      title -> title
    end
  end
end
