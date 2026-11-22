defmodule RegentsWeb.Keyfleet.WorkspaceGraph do
  @moduledoc """
  The workspace's graph, as `Regents.Keyfleet.Graph.Workspace` reads it (its
  `graph` action): its items and links for the Graph view of a workspace's
  Project, laid out by the page's tree canvas (`canvas/2`), and one goal's
  map as a tree for the goal's page (`tree/2`).

  Each item is coloured by its standing (`tone/1`): open, in progress,
  submitted or awaiting review, held up (blocked or disputed), done (accepted,
  reproduced or achieved) or dropped. Items with no standing, such as findings, are
  drawn plain.
  """

  alias RegentsWeb.Keyfleet.ActivityLines
  alias RegentsWeb.Keyfleet.WorkspacePage

  @tones %{
    "open" => :open,
    "todo" => :open,
    "doing" => :doing,
    "done" => :waiting,
    "awaiting_review" => :waiting,
    "blocked" => :held,
    "disputed" => :held,
    "accepted" => :done,
    "reproduced" => :done,
    "achieved" => :done,
    "dropped" => :dropped
  }

  @tone_names [
    open: "Open",
    doing: "In progress",
    waiting: "Awaiting review",
    held: "Blocked or disputed",
    done: "Done",
    dropped: "Dropped",
    plain: "No status"
  ]

  @standing_names %{
    "open" => "Open",
    "todo" => "To do",
    "doing" => "In progress",
    "done" => "Submitted",
    "awaiting_review" => "Awaiting review",
    "blocked" => "Blocked",
    "disputed" => "Disputed",
    "accepted" => "Accepted",
    "reproduced" => "Reproduced",
    "achieved" => "Achieved",
    "dropped" => "Dropped"
  }

  @doc """
  The items and links of `graph`: each item with its tone and the address of
  its page; the tones in use, for the key; each item's links in words, for
  the list; and when the most recently changed item changed (`newest`), nil
  for none. `labels` names each project by its title in the whole fleet's
  view.
  """
  def items(graph, fleet_id, labels) do
    nodes = Enum.map(graph.nodes, &node(&1, fleet_id, labels))

    %{
      nodes: nodes,
      edges: graph.edges,
      tones: tones(nodes),
      owners: graph.owners,
      rows: rows(nodes, graph.edges, Map.new(nodes, &{&1.id, &1})),
      more_nodes?: graph.more_nodes,
      more_edges?: graph.more_edges,
      newest: newest(graph.nodes)
    }
  end

  @doc """
  What the tree canvas draws of `items/3`, for its `data-tree`: a card for
  each item, headed by the Key that made it, or Keyfleet for a starting goal,
  with when it was made (`created`, the log's time by id) and last changed;
  and each link from the item the other came from. What a task produces
  comes from the task; every other link names the item it came from as its
  target: a task delivers on its goal, a review judges its task, a copy
  copies its task.
  """
  def canvas(%{nodes: nodes, edges: edges}, created) do
    %{
      cards:
        for node <- nodes do
          %{
            id: node.id,
            kind: node.kind,
            title: node.title,
            href: node.path,
            patch: true,
            tone: node.tone,
            standing: node.standing,
            author: node.owner || "Keyfleet",
            created: Map.fetch!(created, node.id),
            changed: node.changed_at,
            archived: node.archived?,
            folder: nil
          }
        end,
      links: Enum.map(edges, &link/1)
    }
  end

  @doc "A link of the workspace's graph as the tree canvas runs it, from the item the other came from."
  def link(%{type: "produces"} = edge),
    do: %{id: edge.id, type: edge.type, from: edge.source, to: edge.target}

  def link(edge), do: %{id: edge.id, type: edge.type, from: edge.target, to: edge.source}

  @doc """
  One goal's map as a tree, for the goal's page, from what `items/3` read
  of it: the items linked to the goal, each with the items linked to it in
  turn. Every item stands once, under the first item that reaches it along
  the links, nearest the goal first and the oldest link first. Each says by
  which kind of link it hangs from the one above it (`via`). Items no link
  joins to the goal follow at the top, so none is left out. The goal itself
  is the page, so it is not in the tree.
  """
  def tree(%{nodes: nodes, edges: edges}, goal) do
    by_id = Map.new(nodes, &{&1.id, &1})

    around =
      edges
      |> Enum.reduce(%{}, fn %{source: source, target: target, type: type}, around ->
        around
        |> Map.update(source, [{target, type}], &[{target, type} | &1])
        |> Map.update(target, [{source, type}], &[{source, type} | &1])
      end)
      |> Map.new(fn {id, links} -> {id, Enum.reverse(links)} end)

    {children, seen} = grow([goal], MapSet.new([goal]), %{}, around)

    {loose, children, _seen} =
      Enum.reduce(nodes, {[], children, seen}, fn node, {loose, children, seen} ->
        if MapSet.member?(seen, node.id) do
          {loose, children, seen}
        else
          {children, seen} = grow([node.id], MapSet.put(seen, node.id), children, around)
          {[{node.id, nil} | loose], children, seen}
        end
      end)

    branch(under(children, goal) ++ Enum.reverse(loose), children, by_id)
  end

  # One step out from the items reached last, to the items not yet reached.
  defp grow([], seen, children, _around), do: {children, seen}

  defp grow(frontier, seen, children, around) do
    {next, seen, children} =
      for id <- frontier,
          {other, type} <- Map.get(around, id, []),
          reduce: {[], seen, children} do
        {next, seen, children} ->
          if MapSet.member?(seen, other),
            do: {next, seen, children},
            else:
              {[other | next], MapSet.put(seen, other),
               Map.update(children, id, [{other, type}], &[{other, type} | &1])}
      end

    grow(Enum.reverse(next), seen, children, around)
  end

  defp under(children, id), do: children |> Map.get(id, []) |> Enum.reverse()

  defp branch(entries, children, by_id) do
    for {id, via} <- entries,
        do: %{
          item: Map.fetch!(by_id, id),
          via: via,
          branch: branch(under(children, id), children, by_id)
        }
  end

  # The read answers each item's change as an ISO 8601 time.
  defp newest(nodes) do
    nodes
    |> Enum.map(fn %{changed_at: at} ->
      {:ok, at, _offset} = DateTime.from_iso8601(at)
      at
    end)
    |> Enum.max(DateTime, fn -> nil end)
  end

  @doc "The tone an item is drawn in, by its standing."
  def tone(standing), do: Map.get(@tones, standing, :plain)

  @doc "An item's standing in words, nil for an item with none."
  def standing_name(standing), do: Map.get(@standing_names, standing)

  defp node(node, fleet_id, labels) do
    {kind, _plural} = WorkspacePage.type_name(node.type)
    tone = tone(node.standing)

    %{
      id: node.id,
      type: node.type,
      kind: String.capitalize(kind),
      title: node.title,
      tone: tone,
      standing: standing_name(node.standing),
      owner_key: node.owner_key,
      owner: node.owner_key && ActivityLines.key_name(node.owner_key, nil),
      joined_keys: node.joined_keys,
      project: labels[node.project],
      archived?: node.archived,
      changed_at: node.changed_at,
      path: WorkspacePage.item_path(fleet_id, node.id)
    }
  end

  defp tones(nodes) do
    counts = Enum.frequencies_by(nodes, & &1.tone)

    for {tone, name} <- @tone_names,
        count = counts[tone],
        do: %{tone: tone, name: name, count: count}
  end

  # The list under the canvas: every item, the most recently changed first,
  # with each of its links in words, as its own page says them.
  defp rows(nodes, edges, by_id) do
    links =
      Enum.reduce(edges, %{}, fn edge, links ->
        relation = WorkspacePage.relation_words(edge.type)

        links
        |> Map.update(
          edge.source,
          [{:to, relation, by_id[edge.target]}],
          &[{:to, relation, by_id[edge.target]} | &1]
        )
        |> Map.update(
          edge.target,
          [{:from, relation, by_id[edge.source]}],
          &[{:from, relation, by_id[edge.source]} | &1]
        )
      end)

    for node <- nodes, do: Map.put(node, :links, Enum.reverse(Map.get(links, node.id, [])))
  end
end
