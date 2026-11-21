defmodule Regents.Keyfleet.Graph.Workspace.Read do
  @moduledoc """
  Answers a workspace read from the fleet's read tables, never from its
  writer, so a read never waits behind a write.

  Each read is answered from one read-only snapshot of the tables, so it
  shows the workspace exactly as it stood at `watermark`, the place in the
  fleet's log the tables had reached: a write whose `head_seq` is at or below
  it is in the answer, and nothing past it is.

  `get` answers one object, with where a submitted task's review stands
  (`review`), the Key it belongs to (`owner_key`), and a page of up to 200 of
  its links, oldest first, made after `relations_after`;
  `relations_next_cursor` is the `relations_after` to read the next page
  from, or nil after the last one. `linked` names the item at the other end
  of each of those links by id, with its type, title, standing and whether it
  is archived, so a task's goal, what it depends on and what it produced read
  with it. A task also answers `rerun_check` (`Regents.Keyfleet.Graph.RerunCheck`):
  whether it carries everything a rerun needs, and what it is missing. `changes` answers the copied
  events after `after_seq`, the whole fleet's or, given `project`, those that
  touched that project, oldest first, at most `limit` of them and no more
  than 512 KiB of them unless one event alone is larger;
  `next_cursor` is the `after_seq` to read on from, never past `watermark`,
  so an `after_seq` beyond it still reads the next change, and `run_id` names
  the log they come from. Given `object`, it answers that object's own changes
  alone: its creation, edits, archiving, links and their removal. Given
  `max_bytes`, a page holds no more than that, and a change larger than it
  alone is refused with its size rather than answered past the budget.
  `graph` answers the items its graph draws, the 120 most recently changed,
  the whole fleet's or one project's, type's or owner's, or one goal's map
  (the `:graph` read of objects), with the archived ones only when asked for: each with its type, title, project, standing,
  owner and when it last changed. Beside them the links between them, oldest
  first, at most 600; `more_nodes` and `more_edges` say whether any were left
  out, and `owners` counts the items each Key owns among them.

  `packet` answers a chosen 1 to 20 of one project's objects whole, sorted
  by id, the links whose both ends are among them, and the code, notebook,
  result and evidence addresses they store (`references`). It answers every
  object named or none: an id that names no object of the project, or an
  archived one, is refused as `not_found`, naming none, and a packet larger
  than `max_bytes` as `packet_too_large`, with its size. Nothing outside the
  read tables is read.

  `get` and `changes` name, in `agents`, the agents behind what they
  answer, by wallet: the agent that created the object, or that made each
  change, with the name it gave itself, as the fleet's pages show it beside
  the Key. A goal's or task's agents include each agent that joined it.
  """
  use Ash.Resource.Actions.Implementation

  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Code
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.Errors.RefusedError
  alias Regents.Keyfleet.Graph.Event
  alias Regents.Keyfleet.Graph.RerunCheck
  alias Regents.Keyfleet.Notebooks

  @relation_page 200
  @graph_nodes 120
  @graph_edges 600

  @impl true
  def run(input, opts, context) do
    kind = Keyword.fetch!(opts, :read)
    Graph.in_snapshot(fn -> read(kind, input.arguments, Ash.Context.to_opts(context)) end)
  end

  defp read(:get, %{fleet_id: fleet_id, id: id, relations_after: after_seq}, opts) do
    {_run_id, watermark} = standing(fleet_id, opts)

    case Graph.read_object!(fleet_id, id, [load: [:review, :owner_key]] ++ opts) do
      nil ->
        {:error,
         RefusedError.exception(code: "not_found", reason: "no such object", details: %{id: id})}

      object ->
        {page, rest} =
          fleet_id
          |> Graph.read_relations_touching!(id, after_seq, @relation_page + 1, opts)
          |> Enum.split(@relation_page)

        %{
          object: Map.take(object, [:id, :type, :data, :sys, :version, :review]),
          owner_key: object.owner_key,
          relations: Enum.map(page, &Map.take(&1, [:id, :type, :source, :target, :data])),
          relations_next_cursor: if(rest != [], do: List.last(page).created_seq),
          linked: linked(fleet_id, id, page, opts),
          rerun_check: rerun_check(object),
          watermark: watermark,
          agents: Agents.names_by_wallet([creator(object.sys) | joiners(object.sys)])
        }
    end
  end

  defp read(:changes, %{fleet_id: fleet_id} = args, opts) do
    {run_id, watermark} = standing(fleet_id, opts)

    with {:ok, events, has_more} <- events(args, opts) do
      page = Enum.map(events, &Event.view/1)

      %{
        run_id: run_id,
        events: page,
        next_cursor: if(has_more, do: List.last(page).seq, else: watermark),
        has_more: has_more,
        watermark: watermark,
        agents: page |> Enum.map(&writer(&1.actor)) |> Agents.names_by_wallet()
      }
    end
  end

  defp read(:graph, %{fleet_id: fleet_id} = args, opts) do
    {_run_id, watermark} = standing(fleet_id, opts)
    filter = Map.take(args, [:project, :type, :owner_key, :goal, :archived])

    {nodes, more_nodes} =
      fleet_id
      |> Graph.graph_objects!(filter, [query: [limit: @graph_nodes + 1]] ++ opts)
      |> Enum.split(@graph_nodes)

    {edges, more_edges} =
      case nodes do
        [] ->
          {[], []}

        nodes ->
          fleet_id
          |> Graph.relations_among!(
            Enum.map(nodes, & &1.id),
            [query: [limit: @graph_edges + 1]] ++ opts
          )
          |> Enum.split(@graph_edges)
      end

    %{
      nodes: Enum.map(nodes, &graph_node/1),
      edges: Enum.map(edges, &Map.take(&1, [:id, :type, :source, :target])),
      owners: owners(nodes),
      more_nodes: more_nodes != [],
      more_edges: more_edges != [],
      watermark: watermark
    }
  end

  defp read(:packet, %{fleet_id: fleet_id, project: project, ids: ids} = args, opts) do
    {run_id, watermark} = standing(fleet_id, opts)
    objects = Graph.selected_objects!(fleet_id, project, ids, opts)

    if length(objects) == length(ids) do
      objects = Enum.sort_by(objects, & &1.id)

      relations =
        fleet_id
        |> Graph.relations_among!(ids, opts)
        |> Enum.sort_by(& &1.id)

      %{
        format: "keyfleet.investigation.v1",
        fleet_id: fleet_id,
        project: project,
        run_id: run_id,
        watermark: watermark,
        objects: Enum.map(objects, &packet_object/1),
        relations: Enum.map(relations, &Map.take(&1, [:id, :type, :source, :target, :data])),
        references: Enum.flat_map(objects, &references(fleet_id, &1)),
        complete_for_selection: true
      }
      |> fits(args.max_bytes)
    else
      {:error, RefusedError.exception(code: "not_found", reason: "no such object", details: %{})}
    end
  end

  defp packet_object(object),
    do: Map.take(object, [:id, :type, :version, :owner_key, :review, :data, :sys])

  # A packet is answered whole or refused with its size: nothing in it is
  # ever left out to fit.
  defp fits(packet, max_bytes) do
    case byte_size(Jason.encode!(packet)) do
      bytes when bytes <= max_bytes ->
        packet

      bytes ->
        {:error,
         RefusedError.exception(
           code: "packet_too_large",
           reason: "the packet is #{bytes} bytes, more than max_bytes",
           details: %{bytes: bytes, max_bytes: max_bytes}
         )}
    end
  end

  # The code, notebooks, results and evidence an object cites, as its fields
  # store them, each with the identity its address or its fields carry.
  defp references(fleet_id, %{type: "task", data: data} = object) do
    for field <- ~w(commit_ref notebook_ref result_ref),
        is_binary(data[field]),
        do: reference(fleet_id, object.id, field, data[field], nil)
  end

  defp references(fleet_id, %{type: "evidence", data: data} = object),
    do: [reference(fleet_id, object.id, "source_uri", data["source_uri"], data["digest"])]

  defp references(fleet_id, %{type: "service", data: data} = object) do
    for uri <- Map.get(data, "implementation_refs", []),
        do: reference(fleet_id, object.id, "implementation_refs", uri, nil)
  end

  defp references(
         fleet_id,
         %{type: "review", sys: %{"review" => %{"commit_ref" => uri}}} = object
       ),
       do: [reference(fleet_id, object.id, "sys.review.commit_ref", uri, nil)]

  defp references(_fleet_id, _object), do: []

  defp reference(fleet_id, from, field, uri, digest) do
    %{
      from: from,
      field: field,
      uri: uri,
      digest: digest,
      commit: commit(field, uri),
      saved_output: saved_output(fleet_id, uri)
    }
  end

  # The full hash a code address ends in, as a task's rerun takes it.
  defp commit(field, uri)
       when field in ~w(commit_ref sys.review.commit_ref implementation_refs) do
    hash = Path.basename(URI.parse(uri).path || "")
    if Code.full_hash?(hash), do: hash
  end

  defp commit(_field, _uri), do: nil

  # The saved notebook output an address on the fleet's notebook host names:
  # its notebook, the version or background run that saved it, and when.
  defp saved_output(fleet_id, uri) do
    path = String.replace_prefix(uri, Notebooks.url(fleet_id, ""), "")

    case Notebooks.result(path) do
      {:ok, {notebook, source, saved_at}} ->
        %{notebook: notebook, source: source, saved_at: saved_at}

      :error ->
        nil
    end
  end

  defp graph_node(object) do
    %{
      id: object.id,
      type: object.type,
      title: object.title,
      project: object.project,
      standing: object.standing,
      owner_key: object.owner_key,
      joined_keys: joined_keys(object.sys),
      archived: object.sys["archived"] == true,
      changed_at: object.changed_at
    }
  end

  # The Keys that joined a goal or task, each once, lowest first.
  defp joined_keys(sys) do
    sys
    |> Map.get("joined", [])
    |> Enum.map(& &1["key"]["token_id"])
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Each Key that owns any of the items, lowest first, with how many it owns.
  defp owners(nodes) do
    nodes
    |> Enum.map(& &1.owner_key)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort()
    |> Enum.map(fn {key, items} -> %{key: key, items: items} end)
  end

  # One object's changes: a page of them, cut to `max_bytes` here, as the
  # database cuts a page of the fleet's.
  defp events(%{object: id} = args, opts) when is_binary(id) do
    budget = args[:max_bytes] || Event.page_bytes()

    {events, rest} =
      args.fleet_id
      |> Graph.object_events!(id, args.after_seq, args.limit + 1, opts)
      |> Enum.split(args.limit)

    {page, cut} = within(events, budget)
    fitted(page, args[:max_bytes], cut ++ rest != [])
  end

  defp events(%{fleet_id: fleet_id, after_seq: after_seq, limit: limit} = args, opts) do
    window = args |> Map.take([:project, :max_bytes]) |> Map.reject(&is_nil(elem(&1, 1)))
    project = %{project: args[:project]}
    page = Graph.read_events!(fleet_id, after_seq, limit, window, opts)
    has_more = page != [] and more_after?(fleet_id, List.last(page).seq, project, opts)
    fitted(page, args[:max_bytes], has_more)
  end

  # The first events that fit in `budget` bytes together, and the rest; the
  # first alone when it doesn't fit, so a page without a caller's budget is
  # never empty.
  defp within(events, budget) do
    {page, rest, _left} =
      Enum.reduce(events, {[], [], budget}, fn
        event, {[], [], left} ->
          {[event], [], left - event.byte_size}

        %{byte_size: bytes} = event, {page, [], left} when bytes <= left ->
          {[event | page], [], left - bytes}

        event, {page, rest, left} ->
          {page, [event | rest], left}
      end)

    {Enum.reverse(page), Enum.reverse(rest)}
  end

  # A budget the caller named is never broken: a change larger than it alone
  # is refused with its size, and the caller chooses to raise the budget.
  defp fitted([%{byte_size: bytes, seq: seq} | _rest], max_bytes, _has_more)
       when is_integer(max_bytes) and bytes > max_bytes,
       do:
         {:error,
          RefusedError.exception(
            code: "over_budget",
            reason: "the change at seq #{seq} alone is #{bytes} bytes, more than max_bytes",
            details: %{seq: seq, bytes: bytes}
          )}

  defp fitted(page, _max_bytes, has_more), do: {:ok, page, has_more}

  # The item at the other end of each link on the page, by id, with what a
  # reader needs to judge it without reading it: its type, title, standing
  # and whether it is archived.
  defp linked(_fleet_id, _id, [], _opts), do: %{}

  defp linked(fleet_id, id, page, opts) do
    ids = page |> Enum.map(&if(&1.source == id, do: &1.target, else: &1.source)) |> Enum.uniq()

    fleet_id
    |> Graph.object_titles!(ids, [load: [:standing]] ++ opts)
    |> Map.new(fn other ->
      {other.id,
       %{
         type: other.type,
         title: other.title,
         standing: other.standing,
         archived: other.sys["archived"] == true
       }}
    end)
  end

  defp rerun_check(%{type: "task", data: data}) do
    missing = RerunCheck.missing(data)
    %{ready: missing == [], missing: missing}
  end

  defp rerun_check(_object), do: nil

  defp creator(%{"created_by" => by}), do: agent_wallet(by)

  defp joiners(sys), do: sys |> Map.get("joined", []) |> Enum.map(&agent_wallet/1)

  defp agent_wallet(%{"kind" => "agent", "wallet" => wallet}), do: wallet
  defp agent_wallet(_person), do: nil

  defp writer(actor) do
    case Event.member(actor) do
      {_token_id, "agent", wallet} -> wallet
      _person_or_workspace -> nil
    end
  end

  # A fleet whose log has never been copied reads as an empty log.
  defp standing(fleet_id, opts) do
    case Graph.get_cursor!(fleet_id, opts) do
      nil -> {nil, 0}
      cursor -> {cursor.run_id, cursor.applied_seq}
    end
  end

  defp more_after?(fleet_id, seq, project, opts) do
    Event
    |> Ash.Query.for_read(
      :page,
      Map.merge(project, %{fleet_id: fleet_id, after_seq: seq, limit: 1}),
      opts
    )
    |> Ash.exists?(opts)
  end
end
