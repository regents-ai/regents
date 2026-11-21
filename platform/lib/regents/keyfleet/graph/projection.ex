defmodule Regents.Keyfleet.Graph.Projection do
  @moduledoc """
  Copies a fleet's graph log into the read tables, page by page, from where
  its cursor stands.

  Each page is one database transaction: its events, the objects and links
  they change, and the cursor moved past the page commit together, so a copy that stops part way resumes at the first page
  it had not finished. The cursor moves on only from where the page found
  it, so when two copies run at once, the page of the one that is behind
  rolls back instead of moving the cursor backwards. The cursor moves past
  every event it reads, including the runtime's own bookkeeping, which is
  not copied.

  Each event keeps the projects whose items it touched. A page skips every
  event that touches an item of a deleted project, or one already gone from
  the read tables, and everything such an event would change: a project
  deleted while its last writes were on their way never comes back. Each
  page holds the fleet's cursor from its start, as a project's deletion does
  (`Regents.Keyfleet.Projects.Changes.Forget`), so the two take turns.

  Each page counts the changes it copies into the Atlas in the same
  transaction (`Regents.Keyfleet.Atlas.Count.copied/4`).

  The log names itself with `run_id`, minted when its file was created. A
  cursor from another log, or one past the log's head, was copied from a log
  that is no longer this fleet's: the fleet's read tables and its counted
  graph work in the Atlas are removed and copied again from the beginning.
  """

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Atlas
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.Writer
  alias Regents.Keyfleet.Projects

  @system %System{}
  @page 500
  @tables [Graph.Cursor, Graph.Event, Graph.Object, Graph.Relation, Atlas.Thing, Atlas.Bucket]

  # What a reader of the workspace sees: every change to its objects and
  # links, what each write asks members to look at, and the command record
  # each write leaves.
  @copied ~w(
    object.created patch.applied relation.created relation.removed
    keyfleet.attention keyfleet.command
  )

  # Of a command record, what a reader sees: who asked, for what, and what it
  # did. The authority stamp stays in the log.
  @public_command ~w(principal command_id op result events)

  @doc """
  Copies everything the fleet's log holds beyond the cursor.

  Answers `{:ok, {run_id, watermark}}`, the log and the place in it the read
  tables now reflect, or `{:error, reason}` when the graph could not be read,
  the log changed part way, or another copy moved the cursor first; pages
  copied before that stay copied.
  """
  @spec catch_up(String.t()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  def catch_up(fleet_id) do
    with {:ok, %{"result" => %{"run_id" => run_id, "head_seq" => head}}} <-
           Writer.request(fleet_id, "hello", %{}),
         {:ok, cursor} <-
           fleet_id
           |> Graph.get_cursor!(actor: @system)
           |> of_this_log(fleet_id, run_id, head) do
      read_on(cursor)
    end
  end

  defp of_this_log(%{run_id: run_id, applied_seq: applied} = cursor, _fleet_id, run_id, head)
       when applied <= head,
       do: {:ok, cursor}

  defp of_this_log(cursor, fleet_id, run_id, _head) do
    transact(fn ->
      if cursor, do: Graph.forget_cursor!(cursor, actor: @system)
      Atlas.forget_graph(fleet_id)
      Graph.start_cursor!(%{fleet_id: fleet_id, run_id: run_id}, actor: @system)
    end)
  end

  defp read_on(%{run_id: run_id} = cursor) do
    body = %{after_seq: cursor.applied_seq, limit: @page}

    case Writer.request(cursor.fleet_id, "changes", body) do
      {:ok, %{"result" => %{"run_id" => ^run_id, "events" => [], "has_more" => false}}} ->
        {:ok, {run_id, cursor.applied_seq}}

      {:ok, %{"result" => %{"run_id" => ^run_id} = page}} ->
        %{"events" => events, "next_seq" => next_seq, "has_more" => more?} = page
        cursor |> copy(events, next_seq) |> read_more(more?)

      {:ok, %{"result" => %{"run_id" => other}}} ->
        {:error, {:log_replaced, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_more({:ok, cursor}, true), do: read_on(cursor)
  defp read_more({:ok, cursor}, false), do: {:ok, {cursor.run_id, cursor.applied_seq}}
  defp read_more({:error, reason}, _more?), do: {:error, reason}

  defp copy(cursor, events, next_seq) do
    fleet_id = cursor.fleet_id
    events = Enum.filter(events, &(&1["type"] in @copied))

    transact(fn ->
      held = Graph.hold_cursor!(fleet_id, actor: @system)
      known = known(fleet_id, events)
      events = place(fleet_id, events, known)
      record(fleet_id, events)
      project(fleet_id, events, known.objects)
      Atlas.Count.copied(held, events, known.objects, next_seq)

      with {:ok, cursor} <- Graph.advance_cursor(cursor, %{applied_seq: next_seq}, actor: @system),
           do: cursor
    end)
  end

  defp record(_fleet_id, []), do: :ok

  defp record(fleet_id, events) do
    events
    |> Enum.map(fn event ->
      %{
        fleet_id: fleet_id,
        seq: event["seq"],
        event_id: event["id"],
        type: event["type"],
        actor: event["actor"],
        timestamp: event["timestamp"],
        payload: public_payload(event),
        projects: event["projects"]
      }
    end)
    |> Graph.record_events!(actor: @system)
  end

  defp public_payload(%{"type" => "keyfleet.command", "payload" => payload}),
    do: Map.take(payload, @public_command)

  defp public_payload(%{"payload" => payload}), do: payload

  # What the read tables already hold of the objects, links and events the
  # page's events name: the links a removal names first, then the objects at
  # either end of a link, patched or asked about, and the events a command
  # record names that an earlier page copied.
  defp known(fleet_id, events) do
    created =
      for %{"type" => "object.created", "payload" => p} <- events,
          into: MapSet.new(),
          do: p["object"]["id"]

    linked =
      for %{"type" => "relation.created", "payload" => p} <- events,
          into: MapSet.new(),
          do: p["relation"]["id"]

    removed =
      for %{"type" => "relation.removed", "payload" => p} <- events,
          p["id"] not in linked,
          uniq: true,
          do: p["id"]

    ends =
      fleet_id
      |> Graph.read_relations!(removed, actor: @system)
      |> Map.new(&{&1.id, [&1.source, &1.target]})

    named =
      events
      |> Enum.flat_map(fn
        %{"type" => "patch.applied", "payload" => p} ->
          [p["target"]]

        %{"type" => "relation.created", "payload" => %{"relation" => r}} ->
          [r["source"], r["target"]]

        %{"type" => "keyfleet.attention", "payload" => p} ->
          [p["object_id"]]

        _event ->
          []
      end)
      |> Enum.concat(Enum.concat(Map.values(ends)))
      |> Enum.reject(&(&1 in created))
      |> Enum.uniq()

    objects =
      fleet_id
      |> Graph.read_objects!(named, actor: @system)
      |> Map.new(
        &{&1.id,
         %{
           type: &1.type,
           project: &1.project,
           data: Map.put(&1.data, "sys", &1.sys),
           version: &1.version
         }}
      )

    on_page = MapSet.new(events, & &1["id"])

    earlier =
      for %{"type" => "keyfleet.command", "payload" => p} <- events,
          id <- p["events"],
          id not in on_page,
          uniq: true,
          do: id

    placed =
      fleet_id
      |> Graph.events_with_ids!(earlier, actor: @system)
      |> Map.new(&{&1.event_id, &1.projects})

    %{objects: objects, ends: ends, placed: placed}
  end

  # The page's events, each with the projects it touched, without those that
  # touch a deleted project or an item the read tables no longer hold. A
  # command record touches the projects of the copied events it names.
  defp place(fleet_id, events, known) do
    live = fleet_id |> Projects.projects!(actor: @system) |> MapSet.new(& &1.name)
    of = Map.new(known.objects, fn {id, object} -> {id, object.project} end)

    state = %{live: live, of: of, ends: known.ends, placed: known.placed}
    {kept, _state} = Enum.flat_map_reduce(events, state, &place_one/2)
    kept
  end

  defp place_one(event, state) do
    state = learn(event, state)
    touched = touched(event, state)

    if Enum.all?(touched, &(&1 in state.live)) do
      projects = Enum.uniq(touched)
      {[Map.put(event, "projects", projects)], put_in(state.placed[event["id"]], projects)}
    else
      {[], put_in(state.placed[event["id"]], :gone)}
    end
  end

  defp learn(%{"type" => "object.created", "payload" => %{"object" => o}}, state),
    do: put_in(state.of[o["id"]], o["data"]["sys"]["project"])

  defp learn(%{"type" => "relation.created", "payload" => %{"relation" => r}}, state),
    do: put_in(state.ends[r["id"]], [r["source"], r["target"]])

  defp learn(_event, state), do: state

  defp touched(%{"type" => "object.created", "payload" => %{"object" => o}}, state),
    do: [state.of[o["id"]]]

  defp touched(%{"type" => "patch.applied", "payload" => p}, state), do: [state.of[p["target"]]]

  defp touched(%{"type" => "relation.created", "payload" => %{"relation" => r}}, state),
    do: Enum.map(state.ends[r["id"]], &state.of[&1])

  defp touched(%{"type" => "relation.removed", "payload" => %{"id" => id}}, state),
    do: state.ends |> Map.get(id, [nil]) |> Enum.map(&state.of[&1])

  defp touched(%{"type" => "keyfleet.attention", "payload" => p}, state),
    do: [state.of[p["object_id"]]]

  defp touched(%{"type" => "keyfleet.command", "payload" => p}, state) do
    Enum.flat_map(p["events"], fn id ->
      case state.placed do
        %{^id => :gone} -> [nil]
        %{^id => projects} -> projects
        _not_copied -> []
      end
    end)
  end

  # The page's events folded, in order, over the objects they patch, then
  # written once each.
  defp project(fleet_id, events, known) do
    folded =
      Enum.reduce(
        events,
        %{
          objects: known,
          touched: MapSet.new(),
          links: %{},
          unlinked: MapSet.new()
        },
        &fold/2
      )

    write_objects(fleet_id, folded)
    write_links(fleet_id, folded)
  end

  defp fold(%{"type" => "object.created", "payload" => %{"object" => object}} = event, state) do
    projected = %{type: object["type"], data: object["data"], version: object["version"]}
    touch(state, event, object["id"], projected)
  end

  # The graph's own rule: a patch of an object it does not hold changes
  # nothing. An update merges its value into the object's data; a replace,
  # which only the graph host itself writes, becomes the data. The version a
  # patch reaches is the one it was checked against, plus one.
  defp fold(%{"type" => "patch.applied", "payload" => %{"patch" => patch}} = event, state) do
    %{"target" => id, "op" => op, "value" => value, "expected_version" => expected} = patch

    case state.objects do
      %{^id => object} ->
        patched = %{object | data: patched(op, object.data, value), version: expected + 1}
        touch(state, event, id, patched)

      _missing ->
        state
    end
  end

  defp fold(
         %{"type" => "relation.created", "seq" => seq, "payload" => %{"relation" => rel}},
         state
       ) do
    link = %{
      type: rel["type"],
      source: rel["source"],
      target: rel["target"],
      data: rel["data"],
      created_seq: seq
    }

    %{
      state
      | links: Map.put(state.links, rel["id"], link),
        unlinked: MapSet.delete(state.unlinked, rel["id"])
    }
  end

  defp fold(%{"type" => "relation.removed", "payload" => %{"id" => id}}, state),
    do: %{state | links: Map.delete(state.links, id), unlinked: MapSet.put(state.unlinked, id)}

  defp fold(%{"type" => "keyfleet.attention"}, state), do: state
  defp fold(%{"type" => "keyfleet.command"}, state), do: state

  defp patched("update", data, value), do: Map.merge(data, value)
  defp patched("replace", _data, value), do: value

  # Only a creation or a patch changes an object: it last changed at that
  # event's place and time.
  defp touch(state, %{"seq" => seq, "timestamp" => at}, id, object) do
    changed = Map.merge(object, %{changed_seq: seq, changed_at: at})

    %{
      state
      | objects: Map.put(state.objects, id, changed),
        touched: MapSet.put(state.touched, id)
    }
  end

  defp write_objects(fleet_id, %{objects: objects, touched: touched}) do
    rows =
      for id <- touched do
        %{type: type, data: data, version: version, changed_seq: seq, changed_at: at} =
          Map.fetch!(objects, id)

        {sys, data} = Map.pop!(data, "sys")

        %{
          fleet_id: fleet_id,
          id: id,
          type: type,
          project: Map.fetch!(sys, "project"),
          data: data,
          sys: sys,
          version: version,
          changed_seq: seq,
          changed_at: at
        }
      end

    if rows != [], do: Graph.project_objects!(rows, actor: @system)
  end

  defp write_links(fleet_id, %{links: links, unlinked: unlinked}) do
    if map_size(links) > 0 do
      links
      |> Enum.map(fn {id, link} -> Map.merge(link, %{fleet_id: fleet_id, id: id}) end)
      |> Graph.project_relations!(actor: @system)
    end

    if MapSet.size(unlinked) > 0 do
      Graph.Relation
      |> Ash.Query.for_read(:with_ids, %{fleet_id: fleet_id, ids: MapSet.to_list(unlinked)},
        actor: @system
      )
      |> Graph.remove_relations!(actor: @system)
    end
  end

  # Answers `{:ok, value}` with what `fun` returned; a `fun` that answers
  # `{:error, _}`, or raises, rolls the whole transaction back.
  defp transact(fun), do: Ash.transact(@tables, fun)
end
